# Journal des modifications

<p align="center">
  <a href="../../CHANGELOG.md">English</a> ·
  <a href="CHANGELOG.zh-CN.md">简体中文</a> ·
  <a href="CHANGELOG.zh-TW.md">繁體中文</a> ·
  <a href="CHANGELOG.ja.md">日本語</a> ·
  <a href="CHANGELOG.ko.md">한국어</a> ·
  <a href="CHANGELOG.de.md">Deutsch</a> ·
  <a href="CHANGELOG.es.md">Español</a> ·
  Français ·
  <a href="CHANGELOG.it.md">Italiano</a> ·
  <a href="CHANGELOG.nl.md">Nederlands</a>
</p>

Toutes les modifications notables d’AppPad sont documentées dans ce fichier.
Le format s’appuie sur [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), et le projet suit le [versionnage sémantique](https://semver.org/).

> Ce document est une traduction de [CHANGELOG.md](../../CHANGELOG.md). En cas de divergence, la version anglaise fait foi.

## v1.2.6

### Fixed
- Launchpad : Modifier le nombre de lignes ou de colonnes de la grille ne réorganise plus toutes les pages. Quand la grille s’agrandit, seules les pages qui étaient pleines prennent des icônes au début de la page suivante, les autres restent inchangées ; quand elle se réduit, les icônes qui ne tiennent plus passent au début de la page suivante.

## v1.2.5

### Changed
- Launchpad : les apps en cours de téléchargement depuis l’App Store affichent désormais leur icône à 70 % d’opacité, pour être plus faciles à reconnaître.

### Fixed
- Launchpad : à la fin d’un téléchargement depuis l’App Store, une case vide en pointillés apparaissait brièvement avant l’icône de l’app. L’icône s’affiche désormais directement.
- Launchpad : les apps tout juste installées avec Homebrew ou glissées dans Applications n’affichent plus d’abord l’icône d’app générique.

## v1.2.4

### Added

#### Assistants IA (MCP)
- Configuration de Claude Desktop en un clic : les boutons « Ajouter à Claude Desktop » et « Retirer de Claude Desktop » affichent l’état actuel (Ajouté / Non ajouté / Non installé). Seule l’entrée d’AppPad dans claude_desktop_config.json est modifiée ; vos autres serveurs MCP restent inchangés.
- Si AppPad a été déplacé depuis l’ajout, l’état l’indique et « Ajouter à Claude Desktop » met le chemin à jour.

#### Flux de travail
- Nouveaux flux de travail intégrés « Ajouter AppPad à Claude Desktop » et « Retirer AppPad de Claude Desktop ». Tapez « claude » ou « mcp » dans le panneau des flux de travail pour les trouver.

#### Guide de bienvenue
- La page IA propose désormais les mêmes boutons Ajouter / Retirer pour Claude Desktop.

### Note
- Redémarrez Claude Desktop après avoir ajouté ou retiré AppPad pour appliquer le changement.
- Si Claude Desktop n’est pas installé, rien n’est ajouté et AppPad vous le signale.
- Avant chaque modification, une sauvegarde du fichier précédent est enregistrée à côté sous le nom claude_desktop_config.json.apppad-backup.

## v1.2.3

### Fixed
- Presse-papiers: Les éléments enregistrés sont désormais triés par utilisation la plus récente, comme l’historique. Un élément remonte en tête après avoir été collé ou copié, au lieu de rester dans l’ordre d’enregistrement.

## v1.2.2

### Changed
- Panneau des workflows : « Dernière exécution » dans l’aperçu affiche désormais une icône d’état dans le même style que la vérification de l’argument, en un ton plus clair : ✓ vert en cas de réussite, ✕ rouge en cas d’échec, – gris en cas d’annulation, avec une couleur de texte assortie, pour voir le dernier résultat d’un coup d’œil.
- Panneau des workflows : Une exécution annulée n’est plus affichée en rouge comme un échec.

## v1.2.1

### Changed
- Launchpad: Amélioration du glisser-déposer entre les apps et les dossiers.

### Fixed
- Réglages: Correction d'un problème où la fenêtre Réglages chevauchait d'autres fenêtres à son ouverture.

## v1.2.0

### Changed
- Launchpad : un clic sur une app ferme désormais Launchpad avec la même animation d’agrandissement et de fondu qu’un clic sur un espace vide, au lieu de le faire disparaître instantanément.

## v1.1.9

### Ajouté
- Launchpad : les icônes des apps affichent désormais les mêmes pastilles rouges que le Dock (messages non lus, mises à jour). Les dossiers affichent la somme des pastilles des apps qu’ils contiennent, ou un point rouge lorsque ces apps n’ont que des pastilles textuelles.
- Réglages › Général : nouvel interrupteur « Afficher les pastilles des apps », activé par défaut. Les pastilles sont lues depuis le Dock et nécessitent l’autorisation d’accessibilité ; sans elle, l’interrupteur affiche une indication avec un bouton pour ouvrir Réglages Système.

## v1.1.8

### Modifié
- Apparence : forme des boutons et couleur des interrupteurs affinées.
- Raccourcis : performances de la liste des raccourcis améliorées.
- Clips enregistrés : la gestion des éléments du presse-papiers en double a changé.

### Corrigé
- Correction d’un problème lors du réglage de la largeur du côté gauche.

## v1.1.7

### Modifié
- Apparence : tous les interrupteurs sont désormais verts et tous les boutons partagent la même forme de pilule.
- Désinstallation : page de confirmation de suppression affinée.

## v1.1.6

### Ajouté

#### Guide de bienvenue
- Au premier lancement, AppPad ouvre désormais un guide de bienvenue au lieu du Launchpad : une courte présentation des fonctionnalités, suivie de quelques étapes de configuration. Chaque étape peut être ignorée, et Échap ou ⌘W ferme le guide.
- Pincement à quatre doigts : activez-le ou désactivez-le, voyez quels gestes macOS désactiver et dans quel ordre, et ouvrez les réglages du trackpad en un clic.
- Presse-papiers : activez ou désactivez l’historique, découvrez ses raccourcis et les touches les plus utiles (⌘1–⌘0, ⌘S, ⌘↩), et voyez comment un clic sur l’icône d’une app n’affiche que ce qui a été copié depuis cette app.
- ⌘Space pour les flux de travail : désactivez le raccourci de Spotlight en un clic. Le changement prend effet immédiatement, sans fermer la session, et peut être annulé sur la même page. S’il ne peut pas être modifié automatiquement, le guide renvoie aux réglages du clavier.
- Raccourcis d’apps : essayez en attribuant ⌃⌘J à Safari en un clic, puis ajoutez-en d’autres dans Réglages › Raccourcis d’apps.
- L’IA écrit des flux de travail : activez Assistants IA (MCP), copiez la configuration pour Claude Code ou d’autres clients et essayez les exemples de prompts. Chaque flux de travail écrit par l’IA nécessite toujours votre approbation.
- Autorisations et démarrage : accordez l’accessibilité (nécessaire pour coller et pour la gestion des fenêtres) et activez le lancement à l’ouverture de session, avec un état en direct pour chacun.
- La dernière page liste les raccourcis du Launchpad, du presse-papiers, des éléments enregistrés et des flux de travail ; « Ouvrir AppPad » mène directement au Launchpad.
- Balayez à gauche ou à droite avec deux doigts, ou cliquez ou faites glisser le long des points en bas, pour passer d’une page à l’autre.
- Rouvrez le guide à tout moment depuis Réglages › À propos › Afficher le guide de bienvenue….

### Modifié
- Le guide de bienvenue remplace les indications ponctuelles distinctes sur le pincement et sur Spotlight. Si vous aviez déjà vu ces indications, le guide ne s’ouvre pas de lui-même.
- Les mises à jour automatiques attendent la fermeture du guide de bienvenue.

## v1.1.5

### Modifié
- Launchpad : cliquez sur le nom d’un dossier pour le renommer à tout moment, et plus seulement en mode édition.

### Corrigé
- Launchpad : le nom d’un dossier ne se décale plus vers la gauche après l’avoir renommé avec ↩.

## v1.1.4

### Corrigé
- Correction : les apps fraîchement installées (par exemple via Homebrew) pouvaient afficher une icône vide jusqu’au redémarrage d’AppPad.

## v1.1.3

### Ajouté
- Launchpad : les apps en cours de téléchargement depuis l’App Store apparaissent immédiatement, estompées avec une barre de progression, et redeviennent normales une fois installées.
- Launchpad : la suppression d’une app affiche une barre de progression sous son icône ; l’icône disparaît une fois l’opération terminée.

### Modifié
- Désinstallation : les réglages et données de l’app dans les conteneurs sandbox sont conservés, comme lors d’une suppression depuis le Finder, si bien qu’une réinstallation les restaure.

### Corrigé
- Désinstallation : les apps de l’App Store et les autres apps appartenant au système peuvent de nouveau être supprimées (le Finder demande votre mot de passe ou Touch ID). Les fichiers résiduels dans `/Library` sont supprimés de la même façon.
- Désinstallation : les widgets et extensions de l’app encore en cours d’exécution n’empêchent plus sa suppression.

## v1.1.2

### Modifié
- Launchpad : l’ouverture et la fermeture d’un dossier par un clic sont désormais plus fiables.

## v1.1.1

### Modifié
- Mises à jour : la fenêtre de mise à jour affiche désormais un compte à rebours et se ferme d’elle-même à la fin du délai.

## v1.1.0

### Modifié
- Launchpad : l’ouverture et la fermeture d’un dossier sont désormais plus fluides et plus réactives, avec moins de travail par image pendant l’animation.

## v1.0.9

### Ajouté

#### Launchpad
- La recherche trouve désormais les dossiers par leur nom, y compris en pinyin et par initiales, tout comme les apps.
- Recherchez plusieurs éléments à la fois avec `|` ou `||` ; par exemple, `WeChat | Social` affiche l’app et le dossier ensemble, pour que vous puissiez déposer l’app directement dans le dossier.

### Modifié
- AppPad prend désormais en charge macOS 15 Sequoia et versions ultérieures (auparavant macOS 26 Tahoe ou ultérieur). Les commandes Liquid Glass restent disponibles à partir de macOS 26.

## v1.0.8

### Ajouté

#### Launchpad
- La désinstallation d’une app installée avec Homebrew (`brew install --cask`) la retire désormais aussi de Homebrew : une fois l’app et ses fichiers résiduels placés dans la Corbeille, AppPad exécute `brew uninstall --cask` pour son cask. Sans Homebrew, ou pour les apps qui ne sont pas un cask, rien ne change.
- Si Homebrew ne parvient pas à terminer seul (par exemple quand le cask demande un mot de passe administrateur), AppPad affiche la commande à exécuter dans Terminal, avec un bouton pour la copier.

#### Flux de travail
- Dans le panneau Flux de travail, le résultat d’un argument saisi commence désormais par une coche verte lorsqu’il est valide et par une croix rouge dans le cas contraire.

### Modifié
- En passant du Launchpad au panneau Presse-papiers ou Flux de travail, l’ombre du panneau apparaît désormais en fondu pendant la transformation plutôt qu’après.
- Les ombres des panneaux sont dessinées par AppPad et restent à l’extérieur du panneau. Avec un arrière-plan translucide, les panneaux Presse-papiers et Flux de travail ont désormais exactement l’apparence du Launchpad, avec le même flou et la même transparence, sans assombrissement supplémentaire.
- Panneau Flux de travail : un résultat d’argument valide s’affiche dans la couleur de texte normale au lieu du vert ; un résultat non valide reste en rouge.
- Choisir Launchpad, Presse-papiers ou Flux de travail dans le menu de la barre des menus alors qu’un autre panneau est ouvert bascule désormais de la même manière que ⌘⇧J / ⌘⇧K.

### Corrigé
- Le passage entre les panneaux Presse-papiers et Flux de travail avec ⌘⇧J / ⌘⇧K pouvait provoquer un bref clignotement.
- Ouvrir un panneau depuis la barre des menus alors qu’un autre était ouvert laissait brièvement apparaître le bureau.

## v1.0.7

### Ajouté

#### Assistants IA (MCP)
- Claude, Cursor et d’autres clients MCP peuvent lister et exécuter vos flux de travail en passant un argument, comme dans le panneau Flux de travail. Les résultats sont renvoyés à l’IA au lieu d’apparaître sous forme de notifications.
- Les assistants IA peuvent aussi écrire des flux de travail pour vous. Chaque flux nouveau ou modifié est affiché en entier, scripts compris, et n’est enregistré qu’après un clic sur Installer.
- Les exécutions passent par les mêmes confirmations et demandes d’autorisation que le panneau Flux de travail. Les flux désactivés restent masqués.
- Nouvel onglet Assistants IA (MCP) dans Réglages, sous Flux de travail : activé par défaut, il affiche l’état de la connexion et propose des configurations prêtes à copier pour Claude Desktop, Cursor et Claude Code.
- Si AppPad n’est pas lancé, le client IA le démarre en arrière-plan sans ouvrir le Launchpad.

## v1.0.6

### Ajouté

#### Launchpad
- La recherche conserve les dossiers : une app située dans un dossier apparaît désormais sous la forme de son dossier. Ouvrez-le d’un clic ou avec ↩ ; l’app correspondante est mise en évidence, et un nouvel ↩ l’ouvre.
- Les résultats de recherche peuvent être glissés : faites glisser une app hors du panneau vers le Dock ou dans le Finder.
- Créez des dossiers pendant la recherche : déposez lentement une app sur un autre résultat pour créer un dossier, ou sur un dossier pour l’y ajouter. Les apps sorties d’un dossier ouvert depuis les résultats se déposent de la même façon. Maintenez l’app au bord du panneau pour passer à la page de résultats suivante ou précédente.

### Modifié
- Lorsqu’il ne reste qu’une seule app dans un dossier, celle-ci sort désormais du dossier en grandissant doucement au lieu d’apparaître d’un coup.
- Pendant une recherche, le dossier ouvert, la page de résultats et la sélection sont conservés lorsque la disposition change (réorganisation dans un dossier, renommage, désinstallation), et les résultats gardent leur ordre après une fusion au lieu d’être reclassés.

### Corrigé
- Un clic pendant une animation de dépôt (par exemple sur un dossier en cours de création) pouvait fermer le Launchpad.

## v1.0.5

### Ajouté

#### Mises à jour automatiques
- AppPad se maintient désormais à jour tout seul. Chaque jour à 4 h 00, il recherche une nouvelle version, la télécharge en arrière-plan et l’installe dès qu’aucun panneau n’est ouvert, puis redémarre discrètement sans ouvrir le Launchpad.
- Vérification manquée parce que le Mac était en veille ou éteint ? AppPad la rattrape peu après le réveil et réessaie toutes les 30 minutes si le réseau n’est pas prêt.
- Nouvelle section Mises à jour dans Réglages › À propos : activez ou désactivez les mises à jour automatiques (activées par défaut), choisissez l’heure de vérification, consultez la date de la dernière vérification et vérifiez maintenant.
- « Rechercher des mises à jour… » dans le menu de la barre des menus.
- Si une mise à jour est en attente pendant que vous êtes dans Réglages, « Redémarrer pour mettre à jour » l’installe immédiatement.
- Les mises à jour sont vérifiées par une signature EdDSA avant leur installation.

### Modifié
- Réglages › À propos mentionne Sparkle dans les remerciements.

### Remarque
- Les versions antérieures à 1.0.5 ne peuvent pas se mettre à jour d’elles-mêmes : installez une fois la 1.0.5 depuis le DMG ou avec `brew upgrade --cask apppad` ; les versions suivantes arrivent automatiquement.

## v1.0.4

### Ajouté
- Clips enregistrés : le contenu des éléments texte peut désormais être modifié, en plus de leur nom. Cliquez sur le texte pour ouvrir l’éditeur ; ⌘↩ enregistre, Échap annule. Une modification qui dupliquerait un autre élément est refusée.

### Modifié
- Clips enregistrés : le bouton Copier se transforme brièvement en coche verte après une copie réussie ; la ligne garde sa hauteur.

### Corrigé
- Clips enregistrés : copier un élément ne remplace plus son app source par AppPad. La copie compte désormais comme une utilisation, comme un collage depuis le panneau Presse-papiers, et place l’élément en haut de l’historique.

## v1.0.3

### Ajouté

#### Presse-papiers
- Nouvel onglet « Clips enregistrés » dans Réglages pour parcourir, rechercher et gérer la bibliothèque enregistrée : icône de l’app source, nom, aperçu sur deux lignes et date pour chaque élément, avec les boutons Copier et Retirer.
- Les éléments enregistrés peuvent porter un nom. Les noms sont recherchables dans Réglages comme dans le panneau Presse-papiers, et les éléments nommés affichent leur nom en gras dans la liste.
- ⌘↩ sur n’importe quel élément du presse-papiers l’ouvre dans Réglages › Clips enregistrés, avec le champ du nom prêt à être saisi ; les éléments non enregistrés sont d’abord enregistrés. Également disponible depuis le menu contextuel (« Modifier dans Clips enregistrés »).

#### Sauvegarde et restauration
- Les sauvegardes incluent désormais les noms des éléments. Les anciennes sauvegardes se restaurent comme avant ; lors d’une fusion, un nom déjà défini sur ce Mac est conservé.

### Modifié
- Presse-papiers : supprimez un élément avec ⌘⇧⌫ (au lieu de ⌘⌫), afin que ⌘⌫ dans le champ de recherche efface de nouveau jusqu’au début de la ligne.
- Presse-papiers : « Afficher dans le Finder » passe de ⌘↩ à ⌘⇧↩.

## v1.0.2

### Ajouté

#### Flux de travail
- Nouvelle option « Demander avant d’exécuter » dans l’éditeur de flux de travail : une confirmation apparaît avant l’exécution, que le flux soit lancé depuis le panneau Flux de travail ou depuis Réglages.
- Dans le panneau Flux de travail, la confirmation s’ouvre à l’intérieur du panneau : ↩ exécute, Échap annule, les autres touches sont ignorées. Un ↩ maintenu ou répété rapidement ne confirme jamais.
- Le format des flux de travail gagne un champ facultatif `"confirm": true` ; les fichiers existants qui ne l’ont pas s’exécutent comme avant.

### Modifié
- Le flux intégré « Quitter toutes les apps » (v1.4) demande désormais une confirmation, si bien que Tab ou ↩ dans le panneau Flux de travail ne peuvent plus quitter toutes les apps par accident.

## v1.0.1

### Ajouté

#### Sauvegarde et restauration
- Nouvel onglet Sauvegarde dans Réglages : exportez dans un seul fichier `.apppadbackup` et restaurez-le sur ce Mac ou sur un autre.
- Choisissez ce qui est inclus : les raccourcis d’apps (ainsi que ceux des flux de travail, du presse-papiers et des fenêtres), la disposition du Launchpad avec la taille de sa grille, les flux de travail installés (avec icônes, raccourcis du panneau et état activé/désactivé), l’historique du presse-papiers et la bibliothèque enregistrée.
- La restauration montre le contenu d’une sauvegarde avant toute modification ; choisissez les parties à restaurer et s’il faut fusionner avec l’existant ou le remplacer.
- La fusion ajoute ce qui manque : les versions plus récentes des flux de travail remplacent les anciennes, et les éléments du presse-papiers sont comparés par contenu, si bien que rien n’est dupliqué.
- La disposition du Launchpad est toujours remplacée ; les apps non installées sur ce Mac sont ignorées, et les apps absentes de la sauvegarde sont ajoutées à la fin.
- Les secrets du trousseau et les autorisations « Toujours autoriser » ne sont jamais écrits dans une sauvegarde ; les flux de travail restaurés redemandent l’autorisation lors de leur première exécution.

## v1.0.0

Première version publique. Nécessite macOS 26 Tahoe ou ultérieur (Universal : Apple Silicon + Intel).

### Ajouté

#### Launchpad
- Le Launchpad classique revient sur macOS 26+, avec la disposition par défaut habituelle (les apps système moins utilisées regroupées dans un dossier « Autres »).
- S’ouvre en pinçant avec quatre doigts, depuis la barre des menus ou en cliquant sur AppPad dans le Dock (un nouveau clic le ferme). Un clic annule l’animation du pincement à tout moment.
- Changement de page par balayage à deux doigts ; indicateur de page en points ou en numéros, que l’on peut toucher et parcourir en le faisant glisser avec une loupe Liquid Glass.
- Recherche instantanée, comme le Launchpad de macOS 15 ; résultats classés selon la fréquence et la récence d’utilisation de chaque app.
- Mode édition par appui long sur une icône d’app ou en maintenant ⌥ Option : faites glisser pour réorganiser, déposez des apps les unes sur les autres pour créer des dossiers. Les dossiers peuvent s’étendre sur plusieurs pages.
- Désinstallation propre intégrée : supprimez une app depuis le mode édition et AppPad supprime aussi ses fichiers résiduels.
- La taille de la fenêtre suit l’écran, avec des pourcentages distincts pour la largeur et la hauteur ; en taille maximale, elle peut recouvrir la barre des menus et évite l’encoche.
- S’ouvre sur l’écran situé sous le pointeur (en option) et reste sur le Space où il a été ouvert, comme le Launchpad d’origine.

#### Presse-papiers
- Historique du presse-papiers pour le texte et les images, conservé de façon permanente ; les images survivent même si le fichier d’origine est supprimé.
- Bibliothèque enregistrée pour les éléments fréquents — activez « Enregistrés » à côté du champ de recherche ; les éléments enregistrés apparaissent en premier dans la recherche.
- Ouverture avec ⌘. (bibliothèque enregistrée : ⌘⌥.), collage avec ⌘1–⌘0, volet d’aperçu à droite.
- Icône de l’app source sur chaque élément, filtres pour vos apps les plus utilisées et syntaxe de recherche `AppName::`.
- ⌘↩ affiche le dossier source d’une image dans le Finder.
- Nettoyage de l’historique par ancienneté (dernière heure, jour, semaine… plus d’un an) sans toucher à la bibliothèque enregistrée.

#### Flux de travail
- Panneau Flux de travail (⌘Space) qui exécute des Raccourcis Apple, de l’AppleScript et des scripts shell, et lance des apps depuis la même recherche.
- Arguments : saisissez-les après la première espace, par ex. `Set-Timer 10:00`. Tab complète l’élément sélectionné.
- Flux intégrés : Vider la corbeille, Régler un minuteur, Régler une alarme, Régler le volume, Couper le son, Quitter toutes les apps, et une calculatrice avec notation scientifique.
- Système d’autorisations avec un véritable sandbox pour les flux shell et AppleScript : Autoriser une fois / Ne pas autoriser / Toujours autoriser.
- Importation de flux de travail depuis des fichiers JSON ou des liens, avec identifiants uniques, révisions et noms multilingues.
- Notifications de réussite et d’échec par flux de travail.
- Les apps et les flux de travail partagent un même classement d’utilisation.

#### Gestion des fenêtres
- ⌃⌥← / ⌃⌥→ ancre à gauche / à droite, en alternant ½ → ⅓ → ⅔.
- ⌃⌥↩ agrandit, ⌃⌥⌫ restaure, ⌃⌥⌘↑ / ⌃⌥⌘↓ déplace vers l’écran précédent / suivant.
- Tous les raccourcis sont personnalisables.

#### Raccourcis d’apps
- Raccourcis clavier globaux pour ouvrir n’importe quelle app, avec une liste d’apps de A à Z et une détection des conflits.

#### Apparence et général
- Champ de recherche, indicateur de page et onglets des réglages en Liquid Glass.
- Thème : Auto / Clair / Sombre.
- Arrière-plans : blanc, gris clair, gris foncé, fond d’écran ou couleur personnalisée, chacun avec sa propre transparence et son propre flou pour les thèmes clair et sombre. Les panneaux Presse-papiers et Flux de travail peuvent suivre l’arrière-plan du Launchpad.
- ⌘⇧J / ⌘⇧K bascule entre Launchpad, presse-papiers et flux de travail avec une animation de transformation fluide.
- Uniquement dans la barre des menus (pas d’icône dans le Dock sauf si vous l’y gardez), lancement à l’ouverture de session.
- Passage facultatif à la source de saisie ABC à l’ouverture de chaque panneau.
- Comportement configurable d’Échap (fermer immédiatement, ou effacer d’abord la recherche).
- Localisé en 10 langues : English, Deutsch, Español, Français, Italiano, 日本語, 한국어, Nederlands, 简体中文, 繁體中文.

#### Distribution
- Signé avec un Developer ID et notarié par Apple.
- Installation avec Homebrew : `brew tap umindhub/tap && brew trust umindhub/tap && brew install --cask apppad`.
- Code source sous AGPL-3.0. Les flux de travail intégrés, le format des flux de travail et les flux tiers sous MIT.
