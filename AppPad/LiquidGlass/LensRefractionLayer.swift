import AppKit
import Metal
import QuartzCore

// MARK: - GlassLabelAlignment

/// Label placement inside its slot box (shared by layers + strip render).
enum GlassLabelAlignment: Equatable {
    case center     // horizontal segmented control
    case leading    // vertical sidebar (LTR)
    case trailing   // vertical sidebar (RTL)
}

// MARK: - GlassLabelImages

/// Label images of one slot. `lens*` = one weight step heavier, used only
/// where the label is seen THROUGH the lifted lens.
struct GlassLabelImages {
    let base:       NSImage
    let accent:     NSImage
    let lensBase:   NSImage
    let lensAccent: NSImage
}

// MARK: - LensRefractionLayer
//
// What the lifted lens of GlassSegmentedNSView shows (Metal).
//
// The labels are rendered once into strip textures (overlay coordinates,
// y-down): base + accent color, each in the normal weight and in a one
// step heavier "lens" weight. Every frame a fragment shader draws ONLY
// inside the lens capsule and, for each pixel, samples at a displaced point:
//
//   core     : t = 0 → disp = 0 → labels at 1:1 (NO zoom — same as the
//              macOS 26 Calendar lens); heavier weight cross-faded in
//              with lift
//   rim band : disp = -n · A · g(t),  g(t) = 6.75·t²·(1 - t)  (peak 1)
//              t: 0 at the core boundary → 1 at the edge.
//              g = 0 at both ends → continuous with the core AND with the
//              outside: a letter shows the moment the edge touches it.
//   R / G / B: disp × (1 ± dispersion·t)  → chromatic fringe. Channels
//              with less coverage are filled with the guessed backdrop,
//              so DARK text on a light bar fringes too.
//   bevel    : under the labels, a dark ring at the edge fading inward
//              (exp of the distance to the edge) → glass thickness.
//              A function of distance only → identical all the way round,
//              straight top / bottom stay parallel.
//   bar edge : the track capsule is analytic (SDF). Light just outside /
//              shadow just inside its top & bottom edge, sampled through
//              a stronger rim warp → the bands sit ON the real edge in the
//              middle and bend into the rim near the lens ends. Nothing is
//              re-drawn at a shifted spot → no second contour.
//              Where the edge bends into the rim (the four "corners") the
//              shadow fades out and turns into a soft caustic light — the
//              warp otherwise dragged the shadow into the overhang as dark
//              smudges.
//
// Pixel exactness: strips are 1× backing with pixel-snapped image origins
// (same rule as the CA label layers) and the canvas is on the pixel grid,
// so with no warp the lens output equals the CA labels pixel for pixel.
//
// The bar itself is NOT re-drawn: the real glass track can't be sampled,
// and a synthetic copy showed as extra contours inside the lens.
// Fold-free while A / bandWidth < 0.44 (max slope of g is 2.25).
// Outside the capsule nothing is drawn. A follows lift → identity at 0.
//
// Shader is compiled from source at runtime → no Metal build settings.
// `make()` returns nil when Metal is unavailable; caller falls back.

final class LensRefractionLayer: CAMetalLayer {

    /// Per-frame lens state, overlay points (y-down).
    struct Params {
        var lens:          CGRect
        var rimRefraction: CGFloat   // rim warp amplitude A, pt (0 = none)
        var bezel:         CGFloat   // rim band width, pt
        var dispersion:    CGFloat   // 0…~0.3
        var slotOrigin:    CGFloat   // along-axis start of slot 0
        var slotWidth:     CGFloat   // along-axis slot length
        var activeness:    [CGFloat] // per physical slot, 0…1
        var vertical:      Bool = false   // slots along y instead of x
        /// 0 = normal strips … 1 = lens (heavier) strips.
        var weight:        CGFloat = 0
        /// Opaque gray guess of what lies under the labels (fringe fill).
        var backdrop:      CGFloat = 1
        /// Bevel: black alpha at the lens edge (0 = none).
        var shade:         CGFloat = 0
        /// Bevel falloff distance, pt.
        var shadeWidth:    CGFloat = 4
        /// Bar capsule (overlay pt); .zero → no bar-edge light / shadow.
        var track:         CGRect  = .zero
        /// White alpha just outside the bar edge.
        var barLight:      CGFloat = 0
        /// Black alpha just inside the bar edge.
        var barShade:      CGFloat = 0
        /// Rim warp amplitude for the bar edge, pt.
        var barWarp:       CGFloat = 0
    }

    /// Label strip inputs (overlay points).
    struct StripSpec: Equatable {
        var size:       CGSize
        /// Label box per physical slot; images are placed inside by `alignment`.
        var labelRects: [CGRect]
        var alignment:  GlassLabelAlignment
        var scale:      CGFloat      // px per pt of the strip textures
        var revision:   Int          // bumps when label images change
    }

    static let maxSlots = 16

    /// Flat uniform buffer layout; mirrors the shader's U_* constants.
    private enum U {
        static let origin = 0, scale = 2, center = 3, half = 5, strip = 7
        static let rim = 9, bezel = 10, disp = 11
        static let slot0 = 12, slotW = 13, count = 14, axis = 15
        static let weight = 16, back = 17, shade = 18, shadeW = 19
        static let track = 20, barLight = 24, barShade = 25, barWarp = 26
        static let active = 27
        static let size = active + LensRefractionLayer.maxSlots
    }

    // MARK: Shared Metal state

    private struct Shared {
        let device:   MTLDevice
        let pipeline: MTLRenderPipelineState
        let queue:    MTLCommandQueue
    }

    nonisolated(unsafe) private static let shared: Shared? = {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue  = device.makeCommandQueue() else { return nil }
        do {
            let lib  = try device.makeLibrary(source: shaderSource, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction   = lib.makeFunction(name: "lensVertex")
            desc.fragmentFunction = lib.makeFunction(name: "lensFragment")
            desc.colorAttachments[0].pixelFormat = .bgra8Unorm
            let pipeline = try device.makeRenderPipelineState(descriptor: desc)
            return Shared(device: device, pipeline: pipeline, queue: queue)
        } catch {
            NSLog("LensRefractionLayer: shader setup failed: \(error)")
            return nil
        }
    }()

    static func make() -> LensRefractionLayer? {
        guard shared != nil else { return nil }
        return LensRefractionLayer()
    }

    // MARK: State

    /// [base, accent, lensBase, lensAccent]
    private var textures: [MTLTexture] = []
    private var strip:    StripSpec?

    // MARK: Init

    override init() {
        super.init()
        guard let s = Self.shared else { return }
        device          = s.device
        pixelFormat     = .bgra8Unorm
        colorspace      = CGColorSpace(name: CGColorSpace.sRGB)
        isOpaque        = false
        framebufferOnly = true
        // Present in sync with the CATransaction that moves mask / edges.
        presentsWithTransaction = true
        isHidden = true
    }

    override init(layer: Any) { super.init(layer: layer) }   // presentation copies

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Canvas

    /// Frame in the parent (overlay) layer; must cover every lens position.
    func setCanvas(frame newFrame: CGRect, contentsScale scale: CGFloat) {
        frame         = newFrame
        contentsScale = scale
        let px = CGSize(width:  max(1, (newFrame.width  * scale).rounded()),
                        height: max(1, (newFrame.height * scale).rounded()))
        if drawableSize != px { drawableSize = px }
    }

    // MARK: Label strips

    /// Re-renders the four strips when the spec changes.
    /// `labels[i]` = images of physical slot i (placed in `labelRects[i]`).
    func updateStrip(_ spec: StripSpec, labels: [GlassLabelImages]) {
        guard spec != strip, let device = Self.shared?.device else { return }
        let sets: [[NSImage]] = [labels.map(\.base),     labels.map(\.accent),
                                 labels.map(\.lensBase), labels.map(\.lensAccent)]
        let made = sets.compactMap { Self.makeStripTexture(spec, images: $0, device: device) }
        guard made.count == sets.count else { return }   // retry on next change
        strip    = spec
        textures = made
    }

    private static func makeStripTexture(_ spec: StripSpec, images: [NSImage],
                                         device: MTLDevice) -> MTLTexture? {
        let w = Int((spec.size.width  * spec.scale).rounded(.up))
        let h = Int((spec.size.height * spec.scale).rounded(.up))
        guard w > 0, h > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: w, height: h,
                                  bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // y-down points → memory row 0 = top, matching Metal texture rows.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: spec.scale, y: -spec.scale)

        let ns = NSGraphicsContext(cgContext: ctx, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ns
        for (i, img) in images.enumerated() where i < spec.labelRects.count {
            let box = spec.labelRects[i]
            let x: CGFloat
            switch spec.alignment {
            case .center:   x = box.midX - img.size.width / 2
            case .leading:  x = box.minX
            case .trailing: x = box.maxX - img.size.width
            }
            // Snap the top-left corner to a whole pixel (matches SlotLabelLayer).
            let s = spec.scale
            let r = CGRect(x: (x * s).rounded() / s,
                           y: ((box.midY - img.size.height / 2) * s).rounded() / s,
                           width: img.size.width, height: img.size.height)
            img.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1,
                     respectFlipped: true, hints: nil)
        }
        NSGraphicsContext.restoreGraphicsState()

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

    /// Draws one frame. Call inside the CATransaction that updates the
    /// lens mask / edges so everything lands on the same frame.
    func render(_ p: Params) {
        guard let s = Self.shared, let strip, textures.count == 4,
              frame.width > 0, frame.height > 0,
              let drawable = nextDrawable(),
              let cb = s.queue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture     = drawable.texture
        pass.colorAttachments[0].loadAction  = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor  = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        guard let enc = cb.makeRenderCommandEncoder(descriptor: pass) else { return }

        var u = [Float](repeating: 0, count: U.size)
        u[U.origin]     = Float(frame.minX);  u[U.origin + 1] = Float(frame.minY)
        u[U.scale]      = Float(drawableSize.width / frame.width)
        u[U.center]     = Float(p.lens.midX); u[U.center + 1] = Float(p.lens.midY)
        u[U.half]       = Float(p.lens.width / 2); u[U.half + 1] = Float(p.lens.height / 2)
        // Points actually covered by the strip texture (whole pixels).
        u[U.strip]      = Float(CGFloat(textures[0].width)  / strip.scale)
        u[U.strip + 1]  = Float(CGFloat(textures[0].height) / strip.scale)
        u[U.rim]        = Float(p.rimRefraction)
        u[U.bezel]      = Float(max(p.bezel, 0.5))
        u[U.disp]       = Float(p.dispersion)
        u[U.slot0]      = Float(p.slotOrigin)
        u[U.slotW]      = Float(max(p.slotWidth, 1))
        u[U.count]      = Float(min(max(p.activeness.count, 1), Self.maxSlots))
        u[U.axis]       = p.vertical ? 1 : 0
        u[U.weight]     = Float(min(max(p.weight, 0), 1))
        u[U.back]       = Float(min(max(p.backdrop, 0), 1))
        u[U.shade]      = Float(min(max(p.shade, 0), 1))
        u[U.shadeW]     = Float(max(p.shadeWidth, 0.5))
        if !p.track.isEmpty {
            u[U.track]     = Float(p.track.midX);      u[U.track + 1] = Float(p.track.midY)
            u[U.track + 2] = Float(p.track.width / 2); u[U.track + 3] = Float(p.track.height / 2)
        }
        u[U.barLight]   = Float(min(max(p.barLight, 0), 1))
        u[U.barShade]   = Float(min(max(p.barShade, 0), 1))
        u[U.barWarp]    = Float(max(p.barWarp, 0))
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

    // MARK: Shader

    private static let shaderSource = """
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
