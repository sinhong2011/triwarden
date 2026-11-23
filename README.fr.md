<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Icône de l’application Triwarden">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  Un gestionnaire de mots de passe Mac natif pour <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> et Bitwarden.<br>
  Développé en Swift et SwiftUI pour macOS 26.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.zh-HK.md">粵語</a> · <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> · Français ·
  <a href="README.es.md">Español</a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg"><img src="https://img.shields.io/badge/Télécharger-pour%20macOS-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="Télécharger le dernier DMG de Triwarden pour macOS"></a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml"><img src="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="Licence : GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 ou version ultérieure">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="promo/public/shots/vault-dark.png" width="820" alt="Le coffre de Triwarden en thème sombre">
</p>

> Cette traduction a été synchronisée avec le [README anglais](README.md) le 22 novembre 2026. La version anglaise conserve la liste complète des fonctions et détails techniques.

> **État :** Triwarden est encore en version préliminaire (0.x). Il fonctionne avec de vrais comptes Vaultwarden et Bitwarden
> et est testé avec les deux, mais nous vous conseillons de conserver votre client habituel jusqu’à la version 1.0. Les captures d’écran utilisent le coffre de démonstration intégré.

## Installation

Nécessite macOS 26 (Tahoe) ou une version ultérieure.

```bash
brew install --cask sinhong2011/tap/triwarden
```

Le bouton ci-dessus télécharge directement le dernier DMG signé et notarié. Vous pouvez rechercher une mise à jour signée dans « Réglages › À propos » ; la vérification et l’installation automatiques sont facultatives.

## Bien démarrer

1. Ouvrez Triwarden, choisissez votre serveur Vaultwarden, Bitwarden US ou Bitwarden EU, puis connectez-vous à votre compte existant.
2. Activez Triwarden dans « Réglages Système › Général › Remplissage automatique et mots de passe » pour remplir les mots de passe, clés d’accès et codes de vérification.
3. Utilisez **⌘F** pour rechercher dans le coffre, ou **⇧⌘Espace** pour ouvrir la palette de commandes depuis n’importe quelle app.
   La saisie automatique nécessite l’autorisation Accessibilité pour **Triwarden Auto-Type**. L’extension de navigateur est facultative et se connecte depuis les réglages.

**Hors ligne :** vous pouvez déverrouiller et consulter le coffre chiffré enregistré sur ce Mac. La création, la modification, l’importation et la suppression d’éléments nécessitent une connexion au serveur ; les changements ne sont pas mis en attente.

**Versions officielles et licence payante :** pour un usage personnel, toutes les fonctions restent disponibles sans licence payante et sans limite de durée. Après environ 30 jours, une version officielle non enregistrée peut afficher un rappel d’achat au lancement, au plus une fois par semaine ; une licence définitive le supprime et couvre une personne sur tous ses Mac. L’utilisation d’une version officielle avec des comptes professionnels nécessite une licence payante par personne. Consultez les [conditions de licence payante](docs/LICENSE-TERMS.md).

## Fonctionnalités

**Un coffre natif sur Mac**

- Gérez identifiants, notes sécurisées, cartes, identités, clés SSH, comptes bancaires, permis de conduire et passeports, avec dossiers, favoris, champs personnalisés, pièces jointes, archives et corbeille.
- Utilisez plusieurs comptes Vaultwarden ou Bitwarden à la fois, y compris les coffres partagés et collections, avec synchronisation WebSocket en direct. Connexion par mot de passe, double authentification et authentification unique (SSO).
- Recherchez dans tous les coffres et filtrez par type, dossier, favori, code à usage unique, clé d’accès ou problème Watchtower.
- Ajoutez, téléchargez et supprimez des pièces jointes depuis l’éditeur. La création d’un identifiant depuis l’onglet actif préremplit les informations du site.

**Un accès rapide**

- Depuis n’importe quelle app, utilisez la palette de commandes pour trouver un élément, le copier ou saisir automatiquement le nom d’utilisateur et le mot de passe.
- Configurez des raccourcis globaux et utilisez la barre des menus pour retrouver les identifiants associés, codes à usage unique et générateur.
- L’extension de navigateur remplit et enregistre les identifiants après approbation dans l’app : Safari, Chrome, Edge, Brave, Arc et Firefox, ainsi que Vivaldi, Opera, Helium, Zen, LibreWolf et la plupart des autres navigateurs basés sur Chromium ou Firefox (à connecter dans les réglages). Sur les formulaires d’inscription, elle propose un mot de passe robuste et votre e-mail ou une adresse privée `vous+tag@`, puis demande « Enregistrer cet identifiant ? » directement dans la page. Les clés d’accès utilisent le remplissage automatique de macOS ; l’extension de navigateur ne gère pas encore leur connexion.

**Intégration macOS et outils de sécurité**

- Le remplissage automatique du système prend en charge les mots de passe, clés d’accès et codes à usage unique. Déverrouillez avec Touch ID ou un code PIN.
- Les secrets copiés sont automatiquement effacés du presse-papiers. L’agent SSH peut signer des commits Git avec les clés SSH du coffre.
- Triwarden peut être masqué des captures, enregistrements et partages d’écran. Les serveurs auto-hébergés peuvent utiliser une autorité de certification privée et des en-têtes supplémentaires tels que Cloudflare Access.
- Watchtower détecte les mots de passe faibles, réutilisés, compromis ou non sécurisés, ainsi que les sites où la double authentification n’est pas activée. Les mots de passe réutilisés font l’objet d’un nettoyage guidé : choisissez l’identifiant à conserver, puis modifiez ou supprimez les autres.
- Double authentification, gestion des appareils, accès d’urgence, Send, générateurs de mots de passe et de noms d’utilisateur, et nombreux formats d’importation et d’exportation, dont une base KeePass (.kdbx) protégée par mot de passe, qui s’ouvre dans KeePassXC, KeePassium et Strongbox.

Consultez le [README anglais](README.md) et la [feuille de route](docs/ROADMAP.md) pour la liste exhaustive et les limitations.

## Ligne de commande et clés API locales

Activez **Answer the tw command** dans « Réglages › Développeur », puis installez `tw` avec **Terminal Helper Setup…**.

```bash
tw get github | pbcopy
tw code github
tw status
tw run
tw tools list
tw generate --length 32
tw lock
```

Les clés API locales sont masquées par défaut. Activez « Réglages › Développeur › Show Secrets » pour suivre le parcours guidé : enregistrer une clé → la fournir à un outil ou projet → vérifier l’autorisation → la réutiliser. Consultez le [guide de démarrage](docs/local-api-keys-getting-started.md).
Chaque clé API indique les outils qui l’utilisent. « Access › Permissions » et « Access › History » présentent les autorisations actives et les décisions précédentes.

## Compiler depuis les sources

Nécessite macOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.js et pnpm.

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run
```

Exécutez `make` pour afficher toutes les commandes. Les plus courantes sont `make test`, `make selftest`, `make uitest` et `make snapshots`.

## Sécurité, accessibilité et langues

Votre mot de passe principal et vos clés ne quittent jamais le Mac ; le serveur ne reçoit que des données chiffrées. Consultez [SECURITY.md](SECURITY.md) pour les détails et le signalement privé des vulnérabilités.

Triwarden fournit des libellés VoiceOver, des raccourcis clavier et prend en charge Augmenter le contraste et Réduire les animations. L’app est disponible en English, 繁體中文, 粵語, 简体中文, 日本語, 한국어, Français, Español et ไทย. Les limites connues sont documentées dans [ACCESSIBILITY.md](ACCESSIBILITY.md).

## Assistance et contribution

Pour les questions d’achat ou de produit, écrivez à [support@triwarden.cc](mailto:support@triwarden.cc). Pour les bugs et demandes de fonctionnalités, ouvrez une [issue GitHub](https://github.com/sinhong2011/triwarden/issues). Issues et pull requests sont les bienvenues ; consultez [docs/RELEASING.md](docs/RELEASING.md) pour le processus de publication.

## Licence

Triwarden est un logiciel libre sous [GNU General Public License v3.0](LICENSE). La licence du code ne couvre ni le nom « Triwarden » ni l’icône de l’app ; toute version modifiée doit utiliser son propre nom et sa propre icône. Triwarden n’est affilié ni à Bitwarden, Inc. ni au projet Vaultwarden.
