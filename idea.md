---
name: "FallbackWiFi"
type: "Application macOS menu bar"
theme: "Bascule automatique Wi-Fi vers partage de connexion"
platform: macOS
status: concept
created: 2026-06-23
---

# FallbackWiFi

## Idee

FallbackWiFi est une mini app macOS de barre de menu qui surveille la connexion Wi-Fi active et bascule automatiquement vers un reseau de secours choisi par l'utilisateur, typiquement le partage de connexion du telephone.

Le produit doit rester volontairement simple :

- choisir un Wi-Fi de backup parmi les reseaux connus du Mac
- afficher l'etat de connexion actuel dans la menu bar
- utiliser l'icone "Signal protege" comme symbole principal
- detecter une coupure ou une perte d'acces Internet
- tenter une bascule automatique vers le reseau de backup
- permettre un test manuel depuis le menu

## MVP

Le MVP est une app menu bar SwiftUI/AppKit sans fenetre principale lourde.

Menu attendu :

- statut actuel : connecte, verification, fallback actif, erreur
- reseau actuel
- reseau de backup choisi
- activer/desactiver l'auto-switch
- tester maintenant
- ouvrir les reglages
- quitter

## Reglages

La fenetre de reglages doit rester courte :

- choisir le Wi-Fi de backup parmi les reseaux enregistres
- choisir la couleur de l'icone quand le fallback est actif
- activer/desactiver la bascule automatique
- regler le delai entre deux verifications

Par defaut, l'icone reste monochrome quand le Wi-Fi principal fonctionne. La couleur choisie par l'utilisateur apparait seulement quand FallbackWiFi a bascule sur le reseau de secours ou quand le mode fallback est actif.

Couleurs de depart a proposer :

- vert systeme : fallback actif et stable
- bleu : fallback actif discret
- orange : fallback actif visible
- rouge : fallback actif critique

## Identite visuelle

Direction choisie : option 02, "Signal protege".

L'icone combine un bouclier et un signal Wi-Fi. Elle doit fonctionner comme image template macOS en etat normal, puis etre rendue avec une couleur d'accent configurable en etat fallback actif.

## Contraintes

- L'icone doit rester lisible a petite taille dans la barre de menu.
- L'interface doit ressembler a un utilitaire Mac discret.
- Le backup doit utiliser un reseau deja enregistre dans macOS.
- Les commandes systeme doivent rester transparentes et explicables.
- La couleur de fallback actif doit etre stockee dans les preferences utilisateur.
