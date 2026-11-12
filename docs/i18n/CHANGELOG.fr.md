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

> **Changement de licence :** AppPad jusqu’à v1.4.3 incluse a été publié sous AGPL-3.0. Les versions suivantes sont un logiciel commercial propriétaire.

## v1.7.0

### Modifié
- OCR : Reconnaissance de texte plus rapide et plus fluide.

## v1.6.9

### Added

#### Workbench
- Lorsqu'une recherche de workflow ne donne aucun résultat, une catégorie de marché d'apps et le site web du marché d'apps sont désormais proposés.

### Changed
- Presse-papiers : Amélioration de l'affichage des éléments enregistrés du presse-papiers.

### Fixed
- Réglages : Correction d'un problème de cache de l'avatar dans Compte.

## v1.6.8

### Ajouté

#### Fenêtres
- Redimensionnez les fenêtres sur le quart supérieur gauche, inférieur gauche, supérieur droit ou inférieur droit de l'écran.

#### Workflows
- Les workflows peuvent désormais contrôler les apps : masquer, ouvrir, quitter et définir la taille de la fenêtre.

## v1.6.7

### Fixed
- Launchpad : correction du clignotement du Dock lors du déplacement des icônes.

## v1.6.6

### Modifié
- Launchpad : Amélioration du geste de pincement à quatre doigts, plus fluide et plus réactif.

## v1.6.5

### Modifié
- Launchpad : L’ouverture par pincement à quatre doigts est plus rapide et plus fluide.
- Launchpad : S’ouvre plus rapidement avec le fond d’écran comme arrière-plan.

### Corrigé
- Launchpad : Correction d’un bref à-coup à l’ouverture par pincement juste après le lancement ou après le passage à un autre écran.

## v1.6.4

### Modifié
- Compte : Après une coupure réseau, AppPad réessaie en arrière-plan pendant plusieurs heures, afin que votre connexion et votre licence se rétablissent d’elles-mêmes.

## v1.6.3

### Modifié
- Compte : Vous restez connecté de façon fiable ; un bref problème de réseau ou de serveur ne vous déconnecte plus.

### Corrigé
- Compte : AppPad pouvait vous déconnecter silencieusement en arrière-plan.

## v1.6.2

### Modifié
- Launchpad : l’ouverture par pincement à quatre doigts est plus fluide, même après une longue inactivité.
- Launchpad : s’ouvre plus vite après être passé à un autre écran.

### Corrigé
- Launchpad : la première ouverture après un passage entre l’apparence claire et sombre ne marque plus de pause.

## v1.6.1

### Modifié
- Launchpad : le changement de page et l’ouverture par pincement à quatre doigts sont plus fluides.

### Corrigé
- Launchpad : le premier passage à chaque page après l’ouverture ne saccade plus.

## v1.6.0

### Modifié
- Presse-papiers : Les filtres texte, images et fichiers restent toujours visibles. Les types sans éléments pour les apps sélectionnées apparaissent estompés et restent cliquables (la liste est simplement vide).
- Presse-papiers : Sélectionner des apps ou des types n’estompe plus les autres ; la sélection est indiquée uniquement par sa surbrillance.
- Presse-papiers : Maintenir ⌘ n’affiche plus de pastilles numérotées dans la liste ; les indications ⌘1–⌘0 restent comme avant.

### Corrigé
- Presse-papiers : La barre de filtres ne saute plus lors du changement d’app.

## v1.5.9

### Modifié
- Flux de travail : les scripts s’exécutent dans un bac à sable plus strict et ne peuvent plus ouvrir eux-mêmes des apps, des fichiers ou des liens, ni exécuter des raccourcis. Utilisez une étape « Ouvrir l’URL » pour les liens et une étape « Raccourci » pour les raccourcis.
- Flux de travail : les étapes « Ouvrir l’URL » n’ouvrent plus de fichiers et n’exécutent plus de raccourcis ; tous les autres liens fonctionnent comme avant.
- Flux de travail : les scripts ne peuvent pas contrôler d’autres apps (macOS ne le permet pas) et ne demandent donc plus l’accès Automatisation.
- Flux de travail : les flux écrits par les assistants IA respectent ces règles.

### Corrigé
- Flux de travail : les étapes AppleScript ne s’exécutaient pas, même les plus simples.
- Flux de travail : certains scripts shell qui écrivent du texte sur plusieurs lignes ne s’exécutaient pas.

### Remarque
- Si l’un de vos flux ouvre des apps ou des liens, ou exécute un raccourci depuis un script, remplacez cette partie par une étape « Ouvrir l’URL » ou « Raccourci ».

## v1.5.8

### Modifié
- Sauvegarde : Les workflows intégrés ne sont plus sauvegardés et sont ignorés lors de la restauration ; ils sont toujours fournis avec l’app.

### Corrigé
- Workflows : Les workflows intégrés d’ajout/retrait dans Claude Desktop n’apparaissent plus en double après une mise à jour.
- Sauvegarde : Restaurer une ancienne sauvegarde ne réinstalle plus d’anciens workflows intégrés comme workflows tiers.

### Remarque
- L’état activé/désactivé et les raccourcis du panneau des workflows intégrés ne sont plus restaurés depuis les sauvegardes.

## v1.5.7

### Corrigé
- Launchpad : la première ouverture d’un dossier après le lancement ne saccade plus ; les dossiers s’ouvrent instantanément et en douceur.

## v1.5.6

### Ajouté

#### Launchpad
- Maintenez le bouton gauche de la souris et faites glisser sur un espace vide pour changer de page ; cliquer-glisser sur le trackpad fonctionne aussi. Les dossiers et les résultats de recherche se feuillettent de la même façon.

### Modifié
- Launchpad : Tourner la molette de la souris vers le bas passe désormais à la page suivante, quel que soit le réglage de défilement naturel du système ; le nouvel interrupteur « Défilement naturel des pages à la molette » sous « Défilement rapide des pages » (désactivé par défaut) inverse le sens.
- Réglages : « Défilement rapide des pages au trackpad » s’appelle désormais « Défilement rapide des pages » et accélère aussi le changement de page à la molette : continuez à la tourner pour parcourir plusieurs pages.

### Corrigé
- Launchpad : Les souris à défilement fluide ne pouvaient pas changer de page avec la molette.

## v1.5.5

### Ajouté

#### Marché des flux
- Installez en un clic des flux du Marché des flux sur youmindhub.com. Avant de l’ajouter, AppPad montre ce que fait le flux et les autorisations qu’il demande.
- Réglages › Flux de travail affiche une nouvelle bannière qui ouvre le Marché des flux, avec un lien pour publier vos propres flux.

### Modifié
- Flux de travail : les flux du Marché des flux portent la mention « Marché des flux » avec leur auteur.
- Flux de travail : « Rechercher des mises à jour des flux » met aussi à jour les flux du Marché des flux et vous prévient quand l’un d’eux n’y est plus disponible.

### Remarque
- Les liens d’installation de l’ancienne page du Marché des flux ne fonctionnent plus. Rouvrez le flux sur youmindhub.com.

## v1.5.4

### Ajouts

#### Workflows
- Nouveau workflow intégré « Ouvrir Réglages Système » : tapez « system moniteurs » pour aller directement à cette section ; sans section, il ouvre Réglages Système.
- Tapez le nom d’une section, comme « moniteur » ou « wifi », et les sections de Réglages Système correspondantes apparaissent comme lignes à part ; appuyez sur Retour pour l’ouvrir.
- Les noms fonctionnent dans toutes les langues d’AppPad, y compris les sections de Confidentialité et sécurité comme Caméra, Micro et Enregistrement de l’écran.

## v1.5.3

### Modifié
- À propos: Le lien vers le site officiel pointe désormais vers la nouvelle adresse.

## v1.5.2

### Modifié
- Mises à jour : dans la fenêtre « À jour », le libellé OK s’estompe pendant le compte à rebours et disparaît avant que le bouton qui rétrécit ne l’atteigne, dans toutes les langues.

## v1.5.1

### Modifié
- Assistants IA : Les workflows de script écrits par l’IA utilisent désormais le shell par défaut du Mac et fonctionnent donc de façon plus fiable.
- Mises à jour : Dans la fenêtre « À jour », le libellé du bouton OK rétrécit maintenant avec le bouton pendant le compte à rebours.

### Corrigé
- Assistants IA : Le défilement dans la fenêtre de vérification lorsque l’IA enregistre un workflow n’est plus saccadé.

## v1.5.0

### Modifié
- Réglages : « Défilement rapide des pages » passe de Général à l’onglet AppPad, dans sa propre section « Défilement rapide des pages au trackpad ».

### Corrigé
- Launchpad : les apps dont l’identifiant change à chaque version (par ex. SEGGER J-Link) restent dans leurs dossiers après une mise à jour au lieu de s’éparpiller sur les pages.
- Sauvegarde : la restauration récupère aussi le texte reconnu dans les images du presse-papiers, la recherche trouve donc toujours le texte qu’elles contiennent. Les images des anciennes sauvegardes sont reconnues juste après la restauration.

## v1.4.9

### Modifié
- Presse-papiers : les icônes de filtre apparaissent, disparaissent et glissent désormais en douceur au clic.
- Guide de bienvenue : la page des raccourcis d’apps prend désormais le Finder avec ⌃⌘E comme exemple.

## v1.4.8

### Ajouté

#### Presse-papiers
- Filtrer par type : texte, images ou fichiers, avec les boutons à côté d’Enregistré ou ⌃1 / ⌃2 / ⌃3.
- Le texte des images est reconnu sur ce Mac : la recherche trouve aussi le texte des captures d’écran. Le texte reconnu s’affiche sous l’aperçu de l’image et peut être sélectionné et copié. Désactivable dans Réglages › Presse-papiers.

### Modifié
- Presse-papiers : avec du texte sélectionné dans l’aperçu, ⌘C ne copie que la sélection et le panneau reste ouvert.
- Presse-papiers : les images copiées en JPEG, HEIC, GIF ou WebP sont désormais aussi enregistrées.

### Corrigé
- Presse-papiers : les images copiées depuis WeChat n’étaient pas enregistrées.

### Remarque
- Après la mise à jour, les images existantes sont reconnues progressivement en arrière-plan.

## v1.4.7

### Modifié
- Compte : Le nom de ce Mac correspond désormais par défaut au modèle du Mac (ex. MacBook Pro 16) ; double-cliquez pour le renommer, cliquez ailleurs ou appuyez sur Retour pour enregistrer.
- Compte : L’e-mail et l’Open ID peuvent désormais être sélectionnés et copiés par clic droit.

### Corrigé
- Compte : L’icône Compte dans la barre latérale des Réglages ne devient plus un disque bleu plein une fois sélectionnée.
- Compte : Le bouton « Gérer les appareils… » est désormais aligné verticalement avec sa ligne.

## v1.4.6

### Modifié
- Mises à jour : une mise à jour téléchargée ne redémarre plus AppPad tant que la fenêtre de connexion est ouverte.

### Corrigé
- Mises à jour : AppPad peut désormais être mis à jour sans être connecté. « Rechercher les mises à jour… » (⌘U) se trouve dans la barre des menus et dans la fenêtre de connexion : un problème de serveur qui bloque la connexion peut ainsi être corrigé par une mise à jour.

## v1.4.5

### Corrigé
- Compte : correction de l’erreur « La clé publique de licence est absente de cette version » affichée après la connexion.

## v1.4.4

### Ajouté

#### Compte
- Connexion avec votre compte YouMindHub dans Réglages › Compte.
- Essai gratuit au premier lancement ; achat requis ensuite pour continuer à utiliser AppPad.

### Remarque
- AppPad est désormais une app payante à 4,99 $.

## v1.4.3

### Ajouté

#### Presse-papiers
- ⌥1–8 filtre par l’app correspondante ; ⌘-clic ou ⌘⌥1–8 pour filtrer par plusieurs apps à la fois. Maintenez ⌥ pour afficher les numéros. Jusqu’à 8 filtres d’apps sont affichés.

### Corrigé
- Launchpad : Les dossiers ne saccadent plus à leur première ouverture après le lancement ou après une longue inactivité.

## v1.4.2

### Ajouté

#### Réglages
- Nouvel onglet Faire un don au-dessus d’À propos : soutenez AppPad en scannant le code QR WeChat, ou ajoutez une étoile sur GitHub.

## v1.4.1

### Ajouté

#### Flux de travail
- Sans correspondance, le panneau propose désormais des lignes personnalisables : 10 par défaut, jusqu’à 15. Choisissez une catégorie et un site pour chaque ligne, faites glisser pour réorganiser, supprimez avec −.
- 14 catégories (IA, recherche Web, shopping, réseaux sociaux, articles scientifiques, vidéo, musique, plans et voyages, traduction, actualités, etc.) avec des sites populaires mondiaux et régionaux, ainsi que des URL personnalisées.
- Chaque ligne affiche l’icône du site.

### Modifié
- Flux de travail : la liste remplace les lignes fixes recherche Web / demander à l’IA ; vos choix précédents sont conservés.

### Remarque
- Les icônes des sites sont téléchargées une seule fois depuis chaque site et mises en cache sur votre Mac.

## v1.4.0

### Added

#### Workflows
- Quand rien ne correspond, le panneau propose les lignes « Demander à l’IA » et « Recherche web » avec tout ce que vous avez tapé ; ↩ ou Tab ouvre la ligne sélectionnée (l’IA en premier par défaut).
- Taper une adresse web comme apple.com affiche une ligne « Ouvrir le site web » épinglée en haut.
- La recherche web utilise par défaut le moteur de recherche du navigateur (Safari, Chrome, Edge, Brave, Firefox, etc.).

#### Réglages
- Workflows › Quand rien ne correspond : choisissez le navigateur, le moteur de recherche, l’IA (ChatGPT, ChatGPT Search, Google AI Mode, Perplexity, Claude, Grok, Copilot, Le Chat, 秘塔 AI 搜索) ou une URL personnalisée, et la ligne affichée en premier.

### Note
- Claude, Grok et Copilot remplissent seulement la question ; envoyez-la vous-même sur la page. Gemini ne prend pas en charge les liens, utilisez plutôt Google AI Mode.

## v1.3.9

### Changed
- Launchpad : Déposer une icône ne reconstruit plus toute la page, le déplacement et le regroupement restent fluides.

### Fixed
- Launchpad : Il est désormais possible de saisir une autre icône pendant que la précédente termine son animation, sans clignotement ni blocage.
- Launchpad : Cliquer sur un dossier juste après y avoir déposé une app l’ouvre immédiatement.
- Launchpad : Les icônes encore en train de glisser à leur place peuvent être cliquées et déplacées là où elles s’affichent.

## v1.3.8

### Added

#### Flux de travail
- Bouton Exécuter (⌘S) dans le panneau des flux de travail : exécute le flux sélectionné, garde le panneau ouvert et affiche le résultat sous « Dernière exécution ».
- Les flux de travail intégrés peuvent désormais être consultés (lecture seule) dans les Réglages.

### Changed
- Flux de travail : lancer sans l’argument requis signale désormais l’indication par une icône d’avertissement et une brève secousse.

### Fixed
- Launchpad : la disposition n’est plus effacée lorsqu’une mise à jour ou réinstallation via .pkg prend du temps.

## v1.3.7

### Changed
- Clips enregistrés : Le champ du nom s’étend désormais jusqu’à la date et le contenu est aligné sur le nom ; dans Modifier le contenu, le titre et le nom sont alignés sur le texte.

### Fixed
- Réglages : La fenêtre Réglages passe désormais au premier plan quand elle est ouverte depuis Launchpad, Workflows, Presse-papiers ou la barre des menus.
- Clips enregistrés : ⌘Q et Quitter AppPad fonctionnent désormais lorsque Modifier le contenu ou une confirmation est ouvert.

## v1.3.6

### Added

#### Réglages
- Nouvel interrupteur « Afficher les flèches de changement de panneau » dans Général : affiche ou masque les flèches ← / → à côté des titres Presse-papiers et Flux de travail. ⌘⇧K / ⌘⇧J changent toujours de panneau.
- Nouvel interrupteur « Afficher les indications de raccourcis » dans Général : affiche ou masque la ligne de raccourcis sous les titres Presse-papiers et Flux de travail. Si désactivé, le titre est aligné sur le champ de recherche.
- Les deux sont activés par défaut.

## v1.3.5

### Added

#### Launchpad
- Raccourci clavier facultatif pour ouvrir Launchpad (⌥Espace par défaut, désactivé par défaut) : appuyez à nouveau pour le fermer. Activez-le et modifiez-le dans Réglages › AppPad › Ouvrir avec un raccourci ; une fois activé, il apparaît aussi dans le menu de la barre des menus.

#### Guide de bienvenue
- La page du pincement permet désormais d’activer le raccourci de Launchpad et de choisir un coin actif pour Launchpad.

### Changed
- Sauvegarde : les sauvegardes des raccourcis incluent désormais le raccourci de Launchpad.

## v1.3.4

### Added

#### Launchpad
- Défilement rapide des pages (Réglages › Général, désactivé par défaut) : un court balayage à deux doigts change de page, et un seul balayage peut faire défiler plusieurs pages. Les balayages vers le haut/bas suivent aussi les doigts.
- Avec le défilement rapide activé, maintenez et faites glisser les points de page pour faire défiler les pages en continu ; au relâchement, la page la plus proche se cale. Fonctionne aussi dans les dossiers.

### Changed
- Launchpad : Vous pouvez faire glisser l’icône suivante pendant que la précédente rejoint encore sa place (par exemple un dossier), sans attendre la fin de l’animation.

## v1.3.3

### Added

#### Coins actifs
- Nouveaux coins actifs dans Réglages › AppPad : chaque coin de l’écran peut ouvrir AppPad, les Flux de travail ou le Presse-papiers, ou lancer une action macOS (Mission Control, Fenêtres d’application, Bureau, Centre de notifications, Note rapide, économiseur d’écran, suspension du moniteur, Verrouiller l’écran).
- Maintenez ⌘, ⌥, ⌃ ou ⇧ (ou plusieurs) en choisissant une action pour que ce coin ne fonctionne qu’avec ces touches enfoncées, comme dans macOS.

### Note
- Le Centre de notifications et Note rapide nécessitent l’autorisation d’accessibilité.
- Si un coin est aussi défini dans les coins actifs de macOS, les deux s’exécutent ; AppPad affiche un avertissement avec un raccourci vers les Réglages Système.

## v1.3.2

### Added

#### Workflows
- Nouvelle action intégrée « Préremplir une commande dans Terminal » : ouvre Terminal dans le dossier choisi avec une commande saisie à l’invite. Rien ne s’exécute tant que vous n’appuyez pas sur Retour. `{{input}}` est remplacé par l’argument.

### Changed
- Workflows : « Installer Homebrew » préremplit désormais la commande d’installation officielle dans Terminal ; appuyez sur Retour pour la lancer.
- Workflows : avant qu’un script ne contrôle une autre app, AppPad demande d’abord l’autorisation à macOS, l’app apparaît donc dans Confidentialité et sécurité › Automatisation. Si l’accès est refusé, le workflow s’arrête avec un message clair.
- Assistants IA : l’IA peut écrire des workflows qui préremplissent des commandes dans Terminal ; l’installation de Homebrew par l’IA ne fait aussi que préremplir la commande.

### Note
- Si Terminal demande de mettre fin à un processus en cours à la fermeture de la fenêtre, ajoutez `zsh` aux processus ignorés dans les réglages de Terminal (Profils › Shell › Demander avant de fermer).

## v1.3.1

### Added

#### Flux de travail
- Nouveau flux de travail intégré « Rechercher dans l’App Store » : tapez `mas` ou `appstore` suivi de mots-clés pour ouvrir les résultats directement dans l’App Store.

### Fixed
- Panneau Flux de travail : ⌘1–⌘0 sur un flux qui attend un argument le sélectionne désormais et inscrit son nom, prêt pour l’argument, au lieu de ne rien faire.

## v1.3.0

### Fixed
- Presse-papiers : les résultats de la calculatrice copiés dans AppPad affichent désormais l’icône d’AppPad comme app source au lieu d’un cadre vide.

## v1.2.9

### Added

#### Flux de travail
- Chaque flux de travail indique sa provenance : Intégré (vert), Le mien (bleu, écrit par vous ou enregistré par un assistant IA) ou Tiers (orange, avec le site d’origine ou « Fichier importé »).
- Le panneau des flux de travail signale les lignes tierces par une icône orange ; l’aperçu affiche le lien complet et la date d’import.
- Les demandes d’autorisation indiquent la provenance du flux de travail ; les confirmations d’exécution l’indiquent pour les flux tiers.

### Changed
- Flux de travail : Modifier les étapes ou autorisations d’un flux intégré ou tiers le marque « Modifié » ; un flux tiers reste tiers après modification.
- Flux de travail : Lorsqu’un flux de travail est remplacé par un autre d’une provenance différente, AppPad redemande ses autorisations.

### Fixed
- Flux de travail : Les flux importés pouvaient remplacer les flux intégrés en reprenant leur identifiant ; ils sont désormais ignorés.
- Sauvegarde : La restauration n’écrase plus les flux intégrés ; seuls leur état activé/désactivé et leur raccourci du panneau sont restaurés.

### Note
- Les flux de travail non intégrés ajoutés avant cette version apparaissent comme « Le mien », car leur provenance n’était pas enregistrée.

## v1.2.8

### Added

#### Assistants IA
- Les assistants IA peuvent rechercher, installer et désinstaller des apps avec Homebrew. Seules les apps du catalogue officiel de Homebrew notarisées par Apple sont installées (outils en ligne de commande uniquement depuis l’app), et chaque app est vérifiée à nouveau après l’installation.
- Chaque installation et désinstallation demande d’abord votre confirmation. Vous pouvez la désactiver dans Réglages › Assistants IA ; un avertissement liste alors les risques.
- Si Homebrew est absent, AppPad propose d’ouvrir Terminal avec la commande d’installation officielle.

#### Flux de travail
- Nouveau flux de travail intégré « Installer Homebrew ».

### Changed
- Assistants IA : les confirmations déclenchées par l’IA (installation, désinstallation, enregistrement de flux, exécution, autorisations) apparaissent désormais au premier plan sans faire passer devant les autres fenêtres d’AppPad.

### Note
- Les apps désinstallées avec Homebrew sont supprimées directement, sans passer par la corbeille.
- Les formules et les taps tiers ne sont pas pris en charge. Homebrew n’est détecté que dans /opt/homebrew et /usr/local.

## v1.2.7

### Added

#### Barre des menus
- « Rechercher des mises à jour… » dispose désormais du raccourci ⌘U.

### Fixed
- Barre des menus : Les raccourcis globaux (Workflows, Presse-papiers, raccourcis d’apps et de fenêtres) pressés menu ouvert ferment désormais le menu et s’exécutent aussitôt, au lieu d’attendre sa fermeture.
- Barre des menus : Ouvrir les Réglages avec ⌘, depuis le menu alors que Workflows ou le Presse-papiers est ouvert ne rend plus brièvement transparent le fond du panneau.

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
