<p align="center">
  <img src="AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Le Launchpad d’origine, de retour sur macOS 26+, avec presse-papiers, flux de travail, raccourcis d’apps et gestion des fenêtres.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Site web</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  Français ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.nl.md">Nederlands</a>
</p>

---

## Télécharger

[Télécharger la dernière version](https://github.com/umindhub/AppPad/releases/latest)

## Fonctionnalités

### Launchpad
- Reproduction fidèle du Launchpad classique de macOS, disposition par défaut identique à l’ordre du système
- S’ouvre en pinçant avec quatre doigts, depuis la barre des menus ou en cliquant sur AppPad dans le Dock (un nouveau clic le ferme)
- Dossiers, glisser-déposer pour réorganiser ou créer des dossiers ; appui long sur une icône ou maintien de ⌥ pour le mode édition
- Désinstallation propre intégrée : supprime l’app ainsi que ses fichiers résiduels
- Recherche en grille, indicateur de page (points / numéros), commandes Liquid Glass
- Arrière-plans : blanc / gris clair / gris foncé / fond d’écran / couleur personnalisée, réglages distincts pour l’apparence claire et sombre

### Presse-papiers
- Textes et images conservés de façon permanente
- Tout élément copié peut être enregistré
- `⌘1`–`⌘0` pour coller rapidement, filtre par app source, syntaxe de recherche `NomApp::`, aperçu en direct

### Flux de travail
- `⌘Space` ouvre le panneau Flux de travail : apps et flux de travail classés ensemble selon leur utilisation
- Les flux de travail exécutent des scripts shell, de l’AppleScript, des Raccourcis ou des requêtes HTTP, avec arguments (ex. `time 10`)
- Intégrés : Vider la corbeille, Régler un minuteur, Régler une alarme, Régler le volume, Quitter toutes les apps…
- Autorisations déclarées appliquées par un véritable sandbox (Autoriser une fois / Ne pas autoriser / Toujours autoriser)
- Importez et partagez des flux de travail sous forme de fichiers JSON ou de liens

### Calculatrice
- Saisissez une expression directement dans le champ de recherche du panneau Flux de travail pour calculer (notation scientifique prise en charge)

### Raccourcis d’apps
- Attribuez un raccourci clavier global à n’importe quelle app

### Gestion des fenêtres
- Ancrer à gauche / à droite (½ → ⅓ → ⅔), agrandir, restaurer, déplacer vers un autre écran — tous les raccourcis sont personnalisables

### Autres
- Lancer à l’ouverture de session
- `⌘⇧J` / `⌘⇧K` passe avec une animation entre Launchpad, presse-papiers et flux de travail
- 10 langues : de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Configuration requise

- macOS 26 ou version ultérieure
- Xcode 27 (pour compiler depuis les sources)

## Compilation

1. Ouvrez `AppPad.xcodeproj`
2. Choisissez un schéma : `AppPad Dev`, `AppPad Beta` ou `AppPad`
3. Définissez votre propre équipe de signature, puis compilez et lancez

Les dépendances sont résolues par Swift Package Manager.

## Licence

AppPad utilise une licence mixte :

| Partie | Licence |
| --- | --- |
| Code source de l’app AppPad (tout ce qui n’est pas listé ci-dessous) | [AGPL-3.0](LICENSE) |
| Flux de travail intégrés (`AppPad/Workflow/BuiltinWorkflows.swift`, `*.shortcut`) | [MIT](LICENSE-MIT) |
| Spécification du format des flux de travail | [MIT](LICENSE-MIT) |
| Flux de travail tiers du Workflow Market | [MIT](LICENSE-MIT), © leurs auteurs |

- **AGPL-3.0** : vous pouvez utiliser, modifier et redistribuer AppPad, mais toute œuvre dérivée distribuée ou proposée via un réseau doit être publiée sous AGPL-3.0 avec l’intégralité du code source.
- **Licence commerciale** : pour un usage fermé ou propriétaire, contactez l’auteur via le [site web](https://apppad.youmindhub.com) afin d’obtenir une licence commerciale.
- **MIT pour les flux de travail** : chacun peut librement écrire, partager ou vendre des flux de travail, et implémenter leur format dans d’autres outils, sans obligations AGPL.
- Les flux de travail que vous créez vous appartiennent. Ceux soumis au Workflow Market doivent être sous licence MIT.
- Le nom « AppPad » et son icône ne sont pas couverts par ces licences ; les forks doivent utiliser un autre nom et une autre icône.

## Contribuer

Les issues et pull requests sont les bienvenues. En soumettant une contribution, vous acceptez qu’elle soit publiée sous la licence de la partie modifiée et accordez au mainteneur le droit de la distribuer également sous la licence commerciale.

## Remerciements

- [GRDB.swift](https://github.com/groue/GRDB.swift) — licence MIT

---

© 2026 YouMindHub
