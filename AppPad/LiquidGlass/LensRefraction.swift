import AppKit
import Metal
import QuartzCore

// MARK: - GlassLabelImage

// Pre-rendered label bitmap (pixel-exact at `scale`); size in points.
struct GlassLabelImage {
    let image: CGImage
    let size: CGSize

    // Draws into a y-up bitmap context already scaled to points.
    static func render(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> GlassLabelImage? {
        let w = max(1, Int(ceil(size.width * scale)))
        let h = max(1, Int(ceil(size.height * scale)))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        draw(ctx)
        guard let image = ctx.makeImage() else { return nil }
        return GlassLabelImage(image: image, size: CGSize(width: CGFloat(w) / scale, height: CGFloat(h) / scale))
    }
}

// Label images of one slot. lens* = what the lifted lens shows (one step heavier).
struct GlassLabelSet {
    let base: GlassLabelImage
    let accent: GlassLabelImage
    let lensBase: GlassLabelImage
    let lensAccent: GlassLabelImage
}

// MARK: - LensRefraction
//
// Port of YouMindHub LensRefractionLayer (same shader). Owns a CAMetalLayer instead of
// subclassing it, so no CALayer init isolation issues under MainActor default isolation.
//
// Labels are rendered once into strip textures (overlay coordinates, y-down). Every frame
// the fragment shader draws ONLY inside the lens capsule and samples at a displaced point:
//   core     : labels 1:1, heavier weight cross-faded in with lift
//   rim band : bent inward, RGB split → chromatic fringe
//   bevel    : dark ring at the edge fading inward
//   bar edge : light outside / shadow inside the track edge, bent into the rim
// Shader is compiled from source at runtime; make() returns nil without Metal.

final class LensRefraction {

    // Per-frame lens state, overlay points (y-down).
    struct Params {
        var lens: CGRect
        var rimRefraction: CGFloat      // rim warp amplitude, pt
        var bezel: CGFloat              // rim band width, pt
        var dispersion: CGFloat
        var slotOrigin: CGFloat         // x of slot 0
        var slotWidth: CGFloat
        var activeness: [CGFloat]       // per slot, 0…1
        var weight: CGFloat = 0         // 0 normal … 1 lens strips
        var backdrop: CGFloat = 1       // gray guess under the labels (fringe fill)
        var shade: CGFloat = 0          // bevel alpha at the edge
        var shadeWidth: CGFloat = 4
        var track: CGRect = .zero       // .zero → no bar edge light / shadow
        var barLight: CGFloat = 0
        var barShade: CGFloat = 0
        var barWarp: CGFloat = 0
    }

    // Label strip inputs (overlay points).
    struct StripSpec: Equatable {
        var size: CGSize
        var labelRects: [CGRect]        // label box per slot; images centered inside
        var scale: CGFloat
        var revision: Int               // bumps when label images change
    }

    static let maxSlots = 64

    // Flat uniform layout; mirrors the shader's U_* constants.
    private enum U {
        static let origin = 0, scale = 2, center = 3, half = 5, strip = 7
        static let rim = 9, bezel = 10, disp = 11
        static let slot0 = 12, slotW = 13, count = 14, axis = 15
        static let weight = 16, back = 17, shade = 18, shadeW = 19
        static let track = 20, barLight = 24, barShade = 25, barWarp = 26
        static let active = 27
        static let size = active + LensRefraction.maxSlots
    }

    nonisolated private struct Shared {
        let device: MTLDevice
        let pipeline: MTLRenderPipelineState
        let queue: MTLCommandQueue
    }

    nonisolated(unsafe) private static let shared: Shared? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        do {
            let lib = try device.makeLibrary(source: shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = lib.makeFunction(name: "lensVertex")
            desc.fragmentFunction = lib.makeFunction(name: "lensFragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            let pipeline = try device.makeRenderPipelineState(descriptor: desc)
            return Shared(device: device, pipeline: pipeline, queue: queue)
        } catch {
            NSLog("LensRefraction: shader setup failed: \(error)")
            return nil
        }
    }()

    static func make() -> LensRefraction? {
        guard let s = shared else { return nil }
        return LensRefraction(device: s.device)
    }

    let layer = CAMetalLayer()
    private var textures: [MTLTexture] = []    // [base, accent, lensBase, lensAccent]
    private var strip: StripSpec?

    private init(device: MTLDevice) {
        layer.device = device
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.isOpaque = false
        layer.framebufferOnly = true
        // Present in sync with the CATransaction that moves mask / edges.
        layer.presentsWithTransaction = true
        layer.isHidden = true
        layer.actions = ["position": NSNull(), "bounds": NSNull(), "hidden": NSNull(), "contents": NSNull()]
    }

    // MARK: Canvas

    // Frame in the overlay layer; must cover every lens position.
    func setCanvas(frame newFrame: CGRect, contentsScale scale: CGFloat) {
        layer.frame = newFrame
        layer.contentsScale = scale
        let px = CGSize(width: max(1, (newFrame.width * scale).rounded()),
                        height: max(1, (newFrame.height * scale).rounded()))
        if layer.drawableSize != px { layer.drawableSize = px }
    }

    // MARK: Label strips

    // Re-renders the four strips when the spec changes. labels[i] goes into labelRects[i].
    func updateStrip(_ spec: StripSpec, labels: [GlassLabelSet]) {
        guard spec != strip, let device = Self.shared?.device else { return }
        let sets: [[GlassLabelImage]] = [labels.map(\.base), labels.map(\.accent),
                                         labels.map(\.lensBase), labels.map(\.lensAccent)]
        let made = sets.compactMap { Self.makeStripTexture(spec, images: $0, device: device) }
        guard made.count == sets.count else { return }   // retry on next change
        strip = spec
        textures = made
    }

    private static func makeStripTexture(_ spec: StripSpec, images: [GlassLabelImage],
                                         device: MTLDevice) -> MTLTexture? {
        let w = Int((spec.size.width * spec.scale).rounded(.up))
        let h = Int((spec.size.height * spec.scale).rounded(.up))
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // y-up points; memory row 0 = top row → matches Metal texture rows.
        let s = spec.scale
        ctx.scaleBy(x: s, y: s)
        let heightPt = CGFloat(h) / s
        for (i, img) in images.enumerated() where i < spec.labelRects.count {
            let box = spec.labelRects[i]
            // Same pixel snapping as the CA label layers.
            let x = ((box.midX - img.size.width / 2) * s).rounded() / s
            let yDown = ((box.midY - img.size.height / 2) * s).rounded() / s
            ctx.draw(img.image, in: CGRect(x: x, y: heightPt - yDown - img.size.height,
                                           width: img.size.width, height: img.size.height))
        }

        guard let data = ctx.data else { return nil }
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false)
        desc.usage = .shaderRead
        guard let tex = device.makeTexture(descriptor: desc) else { return nil }
        tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                    withBytes: data, bytesPerRow: w * 4)
        return tex
    }

    // MARK: Render

    // Draws one frame; call inside the CATransaction that updates mask / edges.
    func render(_ p: Params) {
        let frame = layer.frame
        guard let s = Self.shared, let strip, textures.count == 4,
              frame.width > 0, frame.height > 0,
              let drawable = layer.nextDrawable(),
              let cb = s.queue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }

        var u = [Float](repeating: 0, count: U.size)
        u[U.origin] = Float(frame.minX); u[U.origin + 1] = Float(frame.minY)
        u[U.scale] = Float(layer.drawableSize.width / frame.width)
        u[U.center] = Float(p.lens.midX); u[U.center + 1] = Float(p.lens.midY)
        u[U.half] = Float(p.lens.width / 2); u[U.half + 1] = Float(p.lens.height / 2)
        u[U.strip] = Float(CGFloat(textures[0].width) / strip.scale)
        u[U.strip + 1] = Float(CGFloat(textures[0].height) / strip.scale)
        u[U.rim] = Float(p.rimRefraction)
        u[U.bezel] = Float(max(p.bezel, 0.5))
        u[U.disp] = Float(p.dispersion)
        u[U.slot0] = Float(p.slotOrigin)
        u[U.slotW] = Float(max(p.slotWidth, 1))
        u[U.count] = Float(min(max(p.activeness.count, 1), Self.maxSlots))
        u[U.axis] = 0
        u[U.weight] = Float(min(max(p.weight, 0), 1))
        u[U.back] = Float(min(max(p.backdrop, 0), 1))
        u[U.shade] = Float(min(max(p.shade, 0), 1))
        u[U.shadeW] = Float(max(p.shadeWidth, 0.5))
        if !p.track.isEmpty {
            u[U.track] = Float(p.track.midX); u[U.track + 1] = Float(p.track.midY)
            u[U.track + 2] = Float(p.track.width / 2); u[U.track + 3] = Float(p.track.height / 2)
        }
        u[U.barLight] = Float(min(max(p.barLight, 0), 1))
        u[U.barShade] = Float(min(max(p.barShade, 0), 1))
        u[U.barWarp] = Float(max(p.barWarp, 0))
        for (i, a) in p.activeness.prefix(Self.maxSlots).enumerated() { u[U.active + i] = Float(a) }

        enc.setRenderPipelineState(s.pipeline)
        u.withUnsafeBytes { enc.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) }
        for (i, tex) in textures.enumerated() { enc.setFragmentTexture(tex, index: i) }
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        enc.endEncoding()

        cb.commit()
        cb.waitUntilScheduled()   // required by presentsWithTransaction
        drawable.present()
    }

    // MARK: Shader (identical to YouMindHub)

    nonisolated private static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    // Uniform indices (flat float buffer) - keep in sync with enum U.
    #define U_ORIGIN   0   // canvas origin in overlay pt (x, y)
    #define U_SCALE    2   // px per pt
    #define U_CENTER   3   // lens center (x, y)
    #define U_HALF     5   // lens half size (w, h)
    #define U_STRIP    7   // strip size pt (w, h)
    #define U_RIM      9
    #define U_BEZEL   10
    #define U_DISP    11
    #define U_SLOT0   12
    #define U_SLOTW   13
    #define U_COUNT   14
    #define U_AXIS    15   // 0 = slots along x, 1 = along y
    #define U_WEIGHT  16   // 0 normal strips .. 1 lens strips
    #define U_BACK    17   // backdrop gray guess
    #define U_SHADE   18   // bevel: black alpha at the edge
    #define U_SHADEW  19   // bevel: falloff distance (pt)
    #define U_TRACK   20   // bar center (x, y), half size (w, h); w = 0 -> none
    #define U_BLIGHT  24   // bar edge: white alpha just outside
    #define U_BSHADE  25   // bar edge: black alpha just inside
    #define U_BWARP   26   // bar edge: rim warp amplitude (pt)
    #define U_ACTIVE  27

    struct VOut { float4 pos [[position]]; };

    // Full-screen triangle.
    vertex VOut lensVertex(uint vid [[vertex_id]]) {
        float2 p = float2((vid << 1) & 2, vid & 2);
        VOut o;
        o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
        return o;
    }

    // Signed distance to a capsule (negative inside).
    static float capsuleSDF(float2 p, float2 c, float2 h) {
        float r = min(h.x, h.y);
        float2 q = abs(p - c) - (h - r);
        return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    }

    constexpr sampler smp(address::clamp_to_zero, filter::linear);

    // Premultiplied "top over bottom".
    static float4 blendOver(float4 top, float4 bottom) {
        return top + bottom * (1.0 - top.a);
    }

    // Three per-channel samples -> one premultiplied color. Channels with
    // less coverage are filled with the backdrop guess, so dark text on a
    // light bar still splits into colored fringes.
    static float4 chroma(float4 r, float4 g, float4 b, float back) {
        float  a   = max(max(r.a, g.a), b.a);
        float3 col = float3(r.r, g.g, b.b) + back * (a - float3(r.a, g.a, b.a));
        return float4(col, a);
    }

    // Label color at overlay point s: accent over base, normal <-> lens
    // weight by U_WEIGHT, accent weight = activeness of the slot under s.
    static float4 labelAt(float2 s, constant float* u,
                          texture2d<float> baseT,     texture2d<float> accentT,
                          texture2d<float> lensBaseT, texture2d<float> lensAccentT) {
        float2 uv = s / float2(u[U_STRIP], u[U_STRIP + 1]);
        float  w  = u[U_WEIGHT];
        float4 b  = mix(baseT.sample(smp, uv),   lensBaseT.sample(smp, uv),   w);
        float4 a  = mix(accentT.sample(smp, uv), lensAccentT.sample(smp, uv), w);
        int n = int(u[U_COUNT]);
        float along = u[U_AXIS] > 0.5 ? s.y : s.x;
        int i = clamp(int(floor((along - u[U_SLOT0]) / u[U_SLOTW])), 0, n - 1);
        float4 at = a * u[U_ACTIVE + i];
        return blendOver(at, b);
    }

    fragment float4 lensFragment(VOut in [[stage_in]],
                                 constant float* u [[buffer(0)]],
                                 texture2d<float> baseT       [[texture(0)]],
                                 texture2d<float> accentT     [[texture(1)]],
                                 texture2d<float> lensBaseT   [[texture(2)]],
                                 texture2d<float> lensAccentT [[texture(3)]]) {
        float  scale = u[U_SCALE];
        float2 p = in.pos.xy / scale + float2(u[U_ORIGIN], u[U_ORIGIN + 1]);
        float2 c = float2(u[U_CENTER], u[U_CENTER + 1]);
        float2 h = float2(u[U_HALF],   u[U_HALF + 1]);

        float sd    = capsuleSDF(p, c, h);
        float cover = clamp(0.5 - sd * scale, 0.0, 1.0);   // 1px AA edge
        if (cover <= 0.0) { return float4(0.0); }

        // Rim: 0 inside the flat core -> 1 at the edge.
        float t = clamp(1.0 + sd / u[U_BEZEL], 0.0, 1.0);
        float g = 6.75 * t * t * (1.0 - t);               // 0 at both ends, peak 1

        // Outward surface normal from the SDF gradient.
        float e = 0.5;
        float2 n = float2(capsuleSDF(p + float2(e, 0), c, h) - capsuleSDF(p - float2(e, 0), c, h),
                          capsuleSDF(p + float2(0, e), c, h) - capsuleSDF(p - float2(0, e), c, h));
        float nl = length(n);
        n = nl > 1e-4 ? n / nl : float2(0.0);

        // Sample inward along the normal: rim-only warp, core stays 1:1.
        float2 disp = -n * (u[U_RIM] * g);
        float  d    = u[U_DISP] * t;                       // dispersion only in the rim

        float4 cr = labelAt(p + disp * (1.0 + d), u, baseT, accentT, lensBaseT, lensAccentT);
        float4 cg = labelAt(p + disp,             u, baseT, accentT, lensBaseT, lensAccentT);
        float4 cb = labelAt(p + disp * (1.0 - d), u, baseT, accentT, lensBaseT, lensAccentT);

        // Bevel: depends only on the distance to the edge -> uniform ring.
        float  shade = u[U_SHADE] * exp(-max(-sd, 0.0) / u[U_SHADEW]);
        float4 col   = float4(0.0, 0.0, 0.0, shade);       // premultiplied black

        // Bar top / bottom edge through the glass: shadow inside, light
        // outside, warped toward the rim (on the real edge in the core).
        float2 th = float2(u[U_TRACK + 2], u[U_TRACK + 3]);
        if (th.x > 0.0) {
            float2 tc = float2(u[U_TRACK], u[U_TRACK + 1]);
            float  tw = capsuleSDF(p - n * (u[U_BWARP] * g), tc, th);
            float  inside = tw < 0.0 ? exp(tw / 2.5) : 0.0;   // just inside the bent edge
            float  bend   = smoothstep(0.0, 0.35, t);             // 0 straight middle -> 1 bent
            float  sh = u[U_BSHADE] * inside * (1.0 - bend);
            float  li = u[U_BLIGHT] * smoothstep(0.0, 0.6, tw) * (1.0 - smoothstep(0.6, 2.4, tw));
            // Caustic: where the edge bends into the rim, light instead of shadow.
            float  ca = u[U_BLIGHT] * 0.65 * inside
                      * smoothstep(0.0, 0.6, t) * (1.0 - smoothstep(0.85, 1.0, t));
            li = max(li, ca);
            col = blendOver(float4(0.0, 0.0, 0.0, sh), col);
            col = blendOver(float4(li, li, li, li), col);
        }

        return blendOver(chroma(cr, cg, cb, u[U_BACK]), col) * cover;
    }
    """
}
