# LPlayer

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · **Français** · [Deutsch](README.de.md) · [Español](README.es.md)

Un lecteur vidéo local pour macOS, conçu avec AppKit et libmpv. Les raccourcis clavier rendent la navigation, le déplacement dans la vidéo et la lecture fluides, pour vous permettre de vous concentrer sur la vidéo.

## Fonctionnalités

- **Raccourcis clavier.** Parcourez les vidéos, déplacez-vous dans la lecture et ajustez les réglages avec des commandes réactives et personnalisables.
- **Lecture locale.** Ouvrez des fichiers ou des dossiers, glissez des vidéos dans la fenêtre ou ouvrez-les depuis le Finder. La version standard recherche en arrière-plan les autres vidéos du même dossier et les sous-titres correspondants.
- **Aperçus dans la liste de lecture.** Cliquez sur une vidéo pour la lire, ou parcourez la liste au clavier pour afficher un aperçu miniature muet avant de confirmer. Deux dispositions sont disponibles : compacte et avec un grand aperçu.
- **Volume global.** Le réglage du volume s'applique à toutes les vidéos et est conservé lors des changements de fichier et des redémarrages de l'application. L'ancien historique d'une vidéo ne peut pas remplacer le niveau actuel.
- **Reprise et lecture privée.** Retrouvez la position, la vitesse, les sous-titres et la piste audio propres à chaque fichier. La lecture privée n'ajoute ni historique de lecture ni autorisation persistante d'accès aux fichiers.
- **Trackpad et barre de progression.** Pincez pour zoomer jusqu'à 5×, déplacez l'image avec deux doigts et survolez la barre de progression pour afficher un aperçu miniature indépendant.
- **Interface native.** Des commandes AppKit, une barre de lecture qui se masque automatiquement, un logotype Manrope et une barre latérale non modale pour consulter les raccourcis.

L'interface de l'application prend actuellement en charge **l'anglais** et le **chinois simplifié**. Les traductions du README ci-dessus concernent uniquement la documentation ; elles n'ajoutent pas de langues à l'interface de l'application.

## Compiler et lancer

Nécessite macOS 13 ou ultérieur, les outils en ligne de commande Xcode et Homebrew. La compilation locale standard a été validée sur Apple Silicon.

Depuis la racine du dépôt :

```sh
brew install mpv pkg-config
./scripts/build-app.sh
open dist/LPlayer.app
```

Vous pouvez aussi double-cliquer sur [`打开LPlayer.command`](打开LPlayer.command). Ce lanceur compile l'application si nécessaire, puis l'ouvre ; il la recompile après toute modification des sources.

Au démarrage, choisissez **Open Video…**, appuyez sur `⌘O`, déposez une vidéo dans la fenêtre ou essayez l'un des trois films de démonstration inclus. LPlayer peut être sélectionné dans le menu **Ouvrir avec** du Finder ; il ne modifie pas automatiquement le lecteur par défaut du système.

Il s'agit d'une version de développement locale avec une signature ad hoc. Aucun programme d'installation signé avec un certificat Developer ID et notarié n'a été publié.

## Langues et réglages

L'application démarre en **anglais**, indépendamment de la langue de macOS, et mémorise votre choix. Pour passer de l'anglais au chinois simplifié, utilisez **Settings → General → Language** ou **LPlayer → Language**.

Un changement de langue met à jour les menus, les infobulles, les commandes rapides, la liste de lecture, l'aide sur les raccourcis et les messages d'erreur de lecture. Les noms des fichiers multimédias et le texte des sous-titres restent inchangés. Les boîtes de dialogue natives du système utilisent la langue sélectionnée au démarrage de l'application.

Les réglages comprennent **General**, **Shortcuts** et **About**. Ouvrez-les depuis **LPlayer → Settings…**, le menu **More** de la barre de lecture ou le bas des commandes rapides. `⌘,` ouvre directement la page **Shortcuts**. Les réglages généraux comprennent également la configuration de main par défaut et la sensibilité du déplacement de l'image.

## Commandes au clavier

Voici les configurations par défaut actuelles. Les configurations déjà personnalisées conservent leurs raccourcis effectifs lors des mises à jour ; réinitialiser les raccourcis d'une main applique les nouvelles valeurs par défaut.

| Action | Main gauche | Main droite |
| --- | --- | --- |
| Lire / mettre en pause | `Space` | `Space` |
| Vidéo précédente / suivante | `W` / `S` | `I` / `K` |
| Reculer / avancer de 5 secondes | `A` / `D` | `J` / `L` |
| Reculer / avancer de 30 secondes | `Shift+A` / `Shift+D` | `Shift+J` / `Shift+L` |
| Augmenter / diminuer le volume | `Shift+W` / `Shift+S` | `Shift+I` / `Shift+K` |
| Ralentir / accélérer | `Q` / `E` | `U` / `O` |
| Vitesse normale | `R` | `P` |
| Liste de lecture | `T` | `'` (également `B`) |
| Commandes rapides | `C` | `,` |
| Aide sur les raccourcis | `V` | `Y` |
| Plein écran | `F` | `H` |
| Afficher / masquer les sous-titres | `G` | `;` |
| Annuler le déplacement dans la lecture | `Z` | `M` |
| Agrandir / réduire l’image | `=` / `-` | `=` / `-` |
| Adapter la vidéo à la fenêtre | `0` | `0` |

`W/A/S/D` et `I/J/K/L` correspondent à `↑/←/↓/→`. Leur comportement dépend du mode visible :

| Mode | Haut / bas | Gauche / droite | Space / Enter |
| --- | --- | --- | --- |
| Lecture | Vidéo précédente / suivante | Se déplacer de 5 secondes | Space lance la lecture / met en pause |
| Liste de lecture | Sélectionner et afficher un aperçu muet | Se déplacer de 5 secondes dans la vidéo en cours | Lire l'élément sélectionné |
| Commandes rapides | Sélectionner une commande | Modifier sa valeur | Activer ou réinitialiser la commande |

Pendant la lecture, `Shift+↑/↓` règle le volume et `Shift+←/→` déplace la lecture de 30 secondes, comme les lettres correspondantes. Dans la liste de lecture, seules les directions verticales sont réservées à la sélection ; les touches horizontales déplacent la lecture de la vidéo en cours, même si une autre ligne est sélectionnée. Avec Shift, le déplacement est de 30 secondes ; maintenir une touche de déplacement répète l’action. Les commandes rapides conservent toutes les directions, y compris avec Shift, pour naviguer et régler les valeurs. Maintenir une touche de changement de vidéo enfoncée ne fait pas sauter plusieurs vidéos.

Autres raccourcis :

- `⌘O` : ouvrir une vidéo ou un dossier.
- `⌘L` : afficher / masquer la liste de lecture.
- `⌘[` / `⌘]` : vidéo précédente / suivante.
- `⌘N` : activer / désactiver la lecture privée.
- `0` ou `⌘0` : adapter l'image à la fenêtre.
- `?`, `/` ou `⌘/` : afficher / masquer l'aide sur les raccourcis.
- `Esc` : fermer le panneau ou la barre latérale active, puis quitter le plein écran.

L'aide sur les raccourcis est non modale : les commandes de lecture restent disponibles lorsqu'elle est ouverte. Les boîtes de dialogue de fichiers et les champs de texte modifiables conservent la saisie normale.

### Liste de lecture et commandes rapides

La liste de lecture est fermée au démarrage. Un clic de souris lit immédiatement la ligne correspondante ; la navigation au clavier la sélectionne et lance un aperçu muet après une courte pause. `Home` / `End` sélectionne le premier / dernier élément. Enter ou Space confirme sans quitter la navigation dans la liste. Confirmer la vidéo en cours reprend la lecture à sa position actuelle ; une vidéo terminée peut recommencer.

La liste de lecture et les commandes rapides ne peuvent pas être ouvertes en même temps. Les commandes rapides conservent 15 actions : vitesse, volume, zoom, sensibilité du déplacement de l'image, visibilité des sous-titres, décalage des sous-titres, piste audio, piste de sous-titres, configuration de main, lecture privée, ouverture de fichiers ou de dossiers, accès au dossier, liste de lecture, langue et personnalisation des raccourcis. Le bouton fixe **Settings…** en bas du panneau constitue une cible supplémentaire de navigation au clavier.

Le bouton des sous-titres les affiche ou les masque directement. Le bouton de vitesse ouvre les commandes rapides sur la ligne de vitesse ; utilisez les touches de navigation horizontale pour la régler par pas de 0,1×.

### Personnaliser les raccourcis

Dans **Settings → Shortcuts**, recherchez parmi les 29 actions et enregistrez les raccourcis séparément pour chaque main. Les lettres, les chiffres, les touches de fonction et les combinaisons avec modificateurs sont pris en charge. Appuyez sur Esc pour annuler l'enregistrement ou sur Delete pour effacer un raccourci principal modifiable. Les conflits et les raccourcis réservés sont refusés ; les raccourcis fixes de navigation et les alias des menus restent disponibles. Les modifications s'appliquent immédiatement et sont conservées localement.

## Volume, historique et confidentialité

Le volume est une préférence globale du lecteur, commune à tous les fichiers, y compris en lecture privée, et conservée après un redémarrage de l'application. Le champ de volume des anciens enregistrements de reprise est gardé pour assurer la compatibilité du format, mais il n'est plus restauré.

La lecture normale conserve les 30 fichiers les plus récents dans `~/Library/Application Support/PalmPlayer/history.json`. Elle restaure la position, la vitesse, le décalage et la visibilité des sous-titres, ainsi que les pistes audio et de sous-titres sélectionnées. Les fichiers terminés repartent du début. L'écriture de l'historique se fait en arrière-plan ; l'identifiant d'origine de l'application et l'emplacement de l'historique restent compatibles avec l'ancien nom PalmPlayer.

La version locale standard ouvre immédiatement un fichier sélectionné, puis recherche les autres vidéos du même dossier et les sous-titres correspondants sans bloquer la lecture. Cette recherche se limite au dossier concerné, ignore les fichiers cachés et les sous-dossiers, et applique un tri naturel, par exemple les épisodes 1, 2 et 10. La sélection explicite de plusieurs fichiers conserve leur ordre de sélection. À la fin d'une vidéo, la lecture passe à l'élément suivant de la file.

La lecture privée enregistre la progression normale avant son activation, puis cesse de lire ou d'écrire l'historique pour les fichiers nouvellement ouverts. Ces fichiers commencent au début ; l'historique existant est conservé. Le volume global et les préférences de l'application restent enregistrés. Vous pouvez effacer l'historique de lecture depuis le menu **File**.

## Trackpad et aperçus

Pincez au-dessus de la vidéo pour zoomer autour du pointeur. Lorsque l'image est agrandie, faites glisser deux doigts sans appuyer sur le trackpad pour la déplacer ; le mouvement suit les doigts et s'arrête lorsque vous les retirez. La sensibilité est réglable de 25 % à 150 %, avec une valeur par défaut de 100 %. L'image reste dans ses limites, et tout changement de vidéo réinitialise le zoom et le déplacement.

Appuyez sur `=` (ou `+`) pour agrandir et sur `-` pour réduire, par pas de 25 points de pourcentage, entre 100 % et 500 %. Maintenez la touche pour ajuster en continu. Ces touches par défaut sont communes aux deux mains et peuvent être personnalisées dans les réglages.

Touchez deux fois le trackpad avec deux doigts pour alterner entre un zoom 2× et l'adaptation à la fenêtre, ou appuyez sur `0` / `⌘0` pour réinitialiser l'affichage. Les gestes qui commencent au-dessus de la liste de lecture, des commandes ou de la barre latérale d'aide conservent l'interaction propre à cette zone.

Les miniatures de la barre de progression utilisent un décodeur basse résolution séparé et un cache en mémoire, sans modifier la position de lecture principale. Les aperçus animés de la liste de lecture sont eux aussi isolés et muets. Les images d'aperçu ne sont pas enregistrées sur disque.

## Prototype HTML interactif

Un prototype limité au frontend est inclus dans [`prototypes/lplayer`](prototypes/lplayer/README.md). Il utilise des vidéos, des polices et des icônes locales, sans dépendance npm :

```sh
python3 prototypes/lplayer/serve.py
```

Ouvrez <http://127.0.0.1:4178/>. Le prototype possède actuellement une interface en chinois. Ses contextes de raccourcis reproduisent ceux du lecteur natif, et les fonctions nécessitant un décodage natif ou les API macOS sont signalées. Les fichiers locaux sont lus à l'aide d'URL d'objet du navigateur et ne sont pas téléversés ; les formats pris en charge par le navigateur diffèrent de ceux de libmpv. Le prototype n'implémente ni l'historique natif ni le backend des autorisations d'accès aux fichiers.

Les trois films de démonstration inclus sont des clips muets réalisés à partir d'images fixes de paysages générées par IA, avec de lents mouvements de caméra créés avec FFmpeg et des sous-titres SRT ; **ce ne sont pas des prises de vues sur place**. Consultez la [provenance des démonstrations](Resources/Demo/README.txt).

## Validation

Les vérifications de lecture supplémentaires nécessitent les outils en ligne de commande FFmpeg :

```sh
brew install ffmpeg
./scripts/check-core.sh
./scripts/check-viewport.sh
./scripts/make-demo.sh
./scripts/check-engine.sh
./scripts/check-gestures.sh
./scripts/check-thumbnails.sh
./scripts/check-seeking.sh production-final Sources/PalmPlayer
python3 scripts/interaction/run-controller.py
```

Les vérifications de base couvrent les correspondances de touches, les modificateurs, l'historique, la persistance et la migration des raccourcis. Le [banc de test du contrôleur](scripts/interaction/README.md) utilise le véritable gestionnaire avec des médias générés et un stockage isolé, notamment pour vérifier le volume global entre des fichiers avec historique et après un redémarrage. Les rapports générés sont placés dans le dossier ignoré `artifacts/` ; les preuves historiques ne sont pas incluses avec les sources.

Les vérifications du moteur et des gestes peuvent afficher brièvement des fenêtres de test indépendantes. Le banc de test masqué du contrôleur utilise des événements locaux et ne valide ni les entrées physiques du clavier, ni le focus au premier plan, ni les Spaces plein écran, ni le comportement des boîtes de dialogue système. Ces vérifications ne remplacent pas les essais sur de vrais appareils et fichiers multimédias. Consultez les [notes de performance (中文)](docs/PERFORMANCE.md) pour les mesures antérieures et leur périmètre.

## Version sandbox de prévisualisation et distribution

Une version sandbox de prévisualisation distincte utilise des dépendances contrôlées et une identité ainsi qu'un conteneur d'application indépendants. Sa cible documentée est Apple Silicon avec macOS 15 ou ultérieur. Elle n'a été ni soumise au Mac App Store ni approuvée par celui-ci :

```sh
./scripts/build-store-deps.sh
./scripts/build-store-app.sh --preview
./scripts/check-store-app.py
```

La version sandbox ne lit initialement que le fichier sélectionné. Utilisez `⌘⇧O` pour accorder un accès en lecture seule au dossier contenant les autres vidéos et les sous-titres correspondants ; ces autorisations utilisent des signets à portée de sécurité et peuvent être supprimées depuis le menu File. Le mode privé n'ajoute ni autorisation persistante ni historique de lecture.

La version standard embarque les bibliothèques non système réellement utilisées par son exécutable, réécrit leurs chemins de chargement, les valide et signe l'application ad hoc. Chaque compilation remplace `dist/LPlayer.app` de manière atomique après avoir conservé une sauvegarde, sans redémarrer un lecteur en cours d'exécution. La police Manrope incluse ne nécessite pas d'installation système.

Les versions des dépendances et les mentions de licence figurent dans [`Resources/licenses`](Resources/licenses/README.md). La version standard fondée sur Homebrew inclut des composants sous licence GPL ; la version sandbox utilise une configuration de dépendances distincte. Les mentions incluses ne constituent pas une distribution complète des sources correspondantes. Consultez la [préparation de la publication (中文)](docs/APP_STORE_RELEASE.md) et la [validation historique du sandbox (中文)](docs/APP_STORE_VALIDATION.md).

Le rendu utilise actuellement le pipeline OpenGL de libmpv. Le rendu Metal, la recherche de sous-titres en ligne, la synchronisation automatique des sous-titres et les fonctions d'IA ne sont pas implémentés. La fidélité HDR, le passthrough audio, la prise en charge de tous les codecs et la consommation énergétique sur différents appareils n'ont pas été validés de façon exhaustive.
