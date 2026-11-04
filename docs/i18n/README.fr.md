<p align="center">
  <img src="../images/icon.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Ramène le Launchpad d’origine sur macOS 26+ (compatible aussi avec macOS 15), avec presse-papiers, flux de travail, raccourcis d’apps et gestion des fenêtres.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Site web</a> · <a href="CHANGELOG.fr.md">Journal des modifications</a>
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
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

## Installation

### Option 1 : télécharger le DMG

[Télécharger la dernière version](https://github.com/umindhub/AppPad/releases/latest), ouvrez le DMG et faites glisser AppPad dans le dossier Applications.

### Option 2 : Homebrew

```bash
brew tap umindhub/tap
brew trust umindhub/tap
brew install --cask apppad
```

## Fonctionnalités

### Launchpad
- Reproduction fidèle du Launchpad classique de macOS, disposition par défaut identique à l’ordre du système
- S’ouvre en pinçant avec quatre doigts, depuis la barre des menus ou en cliquant sur AppPad dans le Dock (un nouveau clic le ferme)
- Dossiers, glisser-déposer pour réorganiser ou créer des dossiers ; appui long sur une icône ou maintien de ⌥ pour le mode édition
- Désinstallation propre intégrée : supprime l’app ainsi que ses fichiers résiduels
- Recherche en grille, indicateur de page (points / numéros), commandes Liquid Glass (macOS 26+)
- Arrière-plans : blanc / gris clair / gris foncé / fond d’écran / couleur personnalisée, réglages distincts pour l’apparence claire et sombre

### Presse-papiers
- Textes et images conservés de façon permanente
- Tout élément copié peut être enregistré
- `⌘1`–`⌘0` pour coller rapidement, filtre par app source, syntaxe de recherche `NomApp::`, aperçu en direct

### Flux de travail & AI MCP
- `⌘Space` ouvre le panneau Flux de travail : apps et flux de travail classés ensemble selon leur utilisation
- Les flux de travail exécutent des scripts shell, de l’AppleScript, des Raccourcis ou des requêtes HTTP, avec arguments (ex. `time 10`)
- Intégrés : Vider la corbeille, Régler un minuteur, Régler une alarme, Régler le volume, Quitter toutes les apps…
- Autorisations déclarées appliquées par un véritable sandbox (Autoriser une fois / Ne pas autoriser / Toujours autoriser)
- Importez et partagez des flux de travail sous forme de fichiers JSON ou de liens
- Serveur MCP intégré : les assistants IA compatibles MCP peuvent appeler et contrôler directement vos flux de travail
- L’IA peut lire via MCP les règles d’écriture des flux de travail et en créer de nouveaux pour vous
- Les flux de travail lancés par l’IA passent par les mêmes demandes d’autorisation et le même sandbox que les vôtres

### Calculatrice
- Saisissez une expression directement dans le champ de recherche du panneau Flux de travail pour calculer (notation scientifique prise en charge)

### Raccourcis d’apps
- Attribuez un raccourci clavier global à n’importe quelle app

### Gestion des fenêtres
- Ancrer à gauche / à droite (½ → ⅓ → ⅔), agrandir, restaurer, déplacer vers un autre écran — tous les raccourcis sont personnalisables

### Autres
- Lancer à l’ouverture de session
- `⌘⇧K` / `⌘⇧J` passe avec une animation entre Launchpad, flux de travail et presse-papiers
- 10 langues : de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Configuration requise

- macOS 15 ou version ultérieure

## Licence

AppPad est un logiciel commercial propriétaire. © 2026 YouMindHub. Tous droits réservés. Ce dépôt ne contient que les versions publiées et la documentation ; le code source n’est pas public.

| Partie | Licence |
| --- | --- |
| App AppPad | Propriétaire, tous droits réservés |
| Flux de travail intégrés | Partie d’AppPad, propriétaires, tous droits réservés |
| Spécification du format des flux de travail | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/deed.fr), © YouMindHub |
| Flux de travail tiers du Workflow Market | © leurs auteurs, sous la licence choisie par chaque auteur |

- Les flux de travail que vous créez vous appartiennent. Vous décidez comment les licencier, les partager ou les vendre.
- En soumettant un flux de travail au Workflow Market, vous accordez à YouMindHub un droit non exclusif de l’héberger et de le distribuer via AppPad. Vous en conservez les droits d’auteur.
- La spécification du format est sous licence CC BY 4.0 : vous pouvez la copier, l’adapter et la redistribuer à condition de citer AppPad.
- Les flux de travail intégrés ne peuvent pas être extraits ni redistribués séparément d’AppPad.
- Le nom « AppPad » et son icône ne sont couverts par aucune des licences ci-dessus.

## Remerciements

- [GRDB.swift](https://github.com/groue/GRDB.swift) — licence MIT
- [Sparkle](https://github.com/sparkle-project/Sparkle) — licence MIT

---

© 2026 YouMindHub
