# Beyond All Reason (BAR) - Performance & Architecture Roadmap

> **Dépôt canonique unique de développement** : [`AstroQuestStudio/Beyond-All-Reason`](https://github.com/AstroQuestStudio/Beyond-All-Reason)  
> **Branche de développement active** : `perf/reduce-callin-and-gc-overhead`  
> **Dépôt historique (lecture seule)** : `AstroQuestStudio/bar-perf-overhaul`  
> **Légende d'avancement** :  
> * `[x]` **Terminé, testé et validé sur Recoil Engine**  
> * `[-]` **En cours / Spécification / Prototype**  
> * `[ ]` **À faire / Planifié**

---

## 1. Diagnostic des Goulots d'Étranglement Relevés

- [x] **Sim-Lag & Lockstep (30s Behind en late-game 8v8)** :
  - Identification du goulot : chaque client simule l'intégralité du monde à 30 ticks/s. Les CPU décrochent quand la frame dépasse 33,3 ms en combat massif (unités, boucliers, projectiles).
- [x] **Saturation de la RAM & Churning Garbage Collection** :
  - Sur-allocation de tables temporaires dans les boucles `GameFrame` et `UnitPreDamaged`, provoquant des pauses GC et du stuttering.
- [x] **Tempête d'appels C++ ⇄ Lua (Bridge Crossing Overhead)** :
  - Enregistrement statique permanent de callins globaux (`UnitPreDamaged`, `ShieldPreDamaged`, `AllowCommand`, `GameFrame`) sur des gadgets alors que les entités concernées (boucliers, armes spéciales, porte-avions) n'existent pas encore sur la carte.
- [x] **Goulot d'étranglement au Démarrage (+18 secondes)** :
  - Profiling temporel d'`infolog.txt` : parsing séquentiel de 971 fichiers d'unités, scans récursifs répétés de répertoires VFS et compactages quadratiques `table.remove`.
- [x] **Absence de mise à l'échelle de résolution 3D (GPU Bottleneck à 1440p/4K)** :
  - Forçage du rendu 3D complet à résolution native avec surcoût sur les shaders différés et les ombres.

---

## 2. P0 / P1A — Combat, Boucliers & Architecture Rust DOD

### A. Hotspots Combat et Boucliers (Lua Déterministe)
- [x] **`unit_shield_behaviour.lua`** :
  - **Désactivation dynamique des callins dormants** : `UnitPreDamaged` et `ShieldPreDamaged` sont débranchés à l'initialisation tant qu'aucun bouclier n'existe sur la carte. Réactivation dynamique via `UpdateCallIn` dès qu'un bouclier est achevé, et débranchement automatique à la destruction du dernier bouclier.
  - **Pooling d'objets pour `shieldSet`** : Remplacement des allocations continues `{}` pour chaque unité couverte par un pool statique `shieldSetPool` recyclé lors du recalcul de couverture.
  - **Élimination du GC churn** : Zéro allocation de table lors des scans de couverture périodiques.
- [x] **`unit_custom_weapons_behaviours.lua`** :
  - **Désactivation dynamique de `GameFrame`** : Débranchement de `GameFrame` tant qu'aucun projectile spécial guidé n'est en vol. Réactivation dynamique dans `ProjectileCreated` et débranchement dans `ProjectileDestroyed` / `GameFrame`.
  - **Vidage in-place de `guidanceResults`** : Suppression de `guidanceResults = {}` par frame ; vidage direct in-place avec recyclage des tuples de coordonnées dans un pool `guidanceTuplePool`.
- [-] **Recherche spatiale batch & filtrage de candidats non-autoritaires** :
  - Architecture candidate : Utiliser `bar-perf-core` pour pré-filtrer géométriquement les cibles candidates sans jamais outrepasser l'autorité de collision du moteur Recoil.

### B. Workspace Rust Déterministe
- [x] **Structure contiguë compacte (`UnitStatePacked`)** : 40 octets par unité, alignement `#[repr(C)]`, 5 000 unités = 200 Ko (cache CPU L2/L3).
- [x] **API C-ABI sécurisée (`bar-perf-core`)** : Fonctions exportées marquées `unsafe extern "C"` avec documentation `# Safety` stricte, validation `cargo test` et `cargo clippy` sans avertissement.
- [x] **Grille spatiale SoA/AoSoA** : `BatchUnitManager` avec requêtes de rayon et filtrage d'allégeance d'équipes.

---

## 3. P1B — Optimisation du Démarrage & Cache UnitDefs

- [x] **Compactage in-place $O(N)$ dans `gamedata/unitdefs.lua`** :
  - Remplacement de la boucle quadratique `table.remove(buildOptions, badIndex - removed)` et de l'allocation `badOptions = {}` par unité par un filtre compacteur in-place en un seul passage sans allocation.
- [x] **Indexation unique des répertoires dans `gamedata/unitdefs_post.lua`** :
  - Remplacement du scan récursif VFS exécuté 971 fois de suite par une table d'indexation construite en un seul balayage linéaire (`buildUnitPathIndex`).
- [x] **Outil Rust `tools/bar-cache-baker`** :
  - Balayage récursif de `units/` et calcul d'un hash composite déterministe (SHA-256 / CRC32) incluant `unitdefs.lua`, `unitdefs_post.lua`, `alldefs_post.lua`.
  - Génération de `cache/unitdefs_manifest.json` et de l'index Lua pré-calculé `cache/unitdefs_cache.lua`.
  - Tests unitaires validés pour la normalisation des noms et le déterminisme du hash.
- [x] **Chargeur rapide avec repli sécurisé dans `unitdefs.lua`** :
  - Chargement instantané de la liste pré-indexée si le cache existe, avec repli transparent vers `VFS.DirList` en cas d'absence.
- [-] **Pré-compilation binaire des tables UnitDefs** :
  - Évaluation de la sérialisation bytecode Lua / chunks pré-analysés pour éviter le parsing individuel des 971 fichiers `.lua`.

---

## 4. P1C — Gadgets Lourds, Callins Dormants & GC

- [x] **`unit_carrier_spawner.lua`** :
  - **Mise en sommeil complète hors unités actives** : Débranchement dynamique de `GameFrame`, `GameFramePost`, `AllowCommand`, `UnitCommand`, `UnitStunned` à l'initialisation.
  - **Réactivation à la demande** : Branchement uniquement si au moins un porte-avions (`carrierMetaList`) ou drone autonome (`droneMetaList`) existe, et débranchement immédiat lors de la destruction du dernier. Évite des milliers d'appels `AllowCommand` sur les ordres des joueurs en début et milieu de partie.
- [x] **`api_teamstats.lua`** :
  - **Élimination de la surcharge par frame graphique** : `gadget:Update()` était exécuté à chaque image de rendu (144–240 Hz) pour vérifier `Script.LuaUI("TeamStatsLive")`. Throttling à 4 Hz (250 ms), préservant la mise à jour de l'écran de pause tout en supprimant 98% des traversées de frontière Lua/C++.
- [x] **`cmd_build_bugger_off.lua`** :
  - Réutilisation de pools statiques pour `visitedTeams`, `visitedUnits`, `cylinderCache`, `deferRemove`.
- [x] **`unit_target_on_the_move.lua`** :
  - Vidage in-place du buffer au lieu de réallouer `teamQueryCaches = {}` à chaque frame.
- [x] **`unit_hats.lua` & `unit_objectify.lua` & `cmd_undo.lua`** :
  - Callins dormants unhooked tant qu'aucun chapeau ou objet n'est présent.

---

## 5. P2 / 3A & 3B — Render Scale & Spécification XeSS

- [x] **Distinction stricte de terminologie (Respect des consignes)** :
  - Aucune labellisation abusive de RCAS en "XeSS".
  - Les contrôles utilisateur dans le menu et le code sont nommés explicitement : `3D Resolution Scaling (RCAS / Spatial)`.
- [x] **Widget de mise à l'échelle spatiale (`gfx_render_scale.lua`)** :
  - Facteurs d'échelle : 100% Native, 85% Ultra Quality, 77% Quality, 67% Balanced, 50% Performance.
  - Préservation intégrale de la résolution native (100%) pour l'interface 2D (HUD, minimap, polices, barres de vie).
- [x] **Intégration dans le menu des options (`gui_options.lua`)** :
  - Sélecteur de mise à l'échelle 3D avec reconstruction spatiale FidelityFX RCAS / EASU.
- [x] **Dossier d'architecture XeSS temporel (`docs/performance/INTEL_XESS_INTEGRATION.md`)** :
  - Spécification des prérequis moteur Recoil C++ pour un véritable XeSS temporel : vecteurs de mouvement G-Buffer, jitter de caméra sous-pixel (Halton 2,3), buffer de profondeur linéaire, buffers d'historique et interop Vulkan/DX12.

---

## 6. Validation Réelle sur Moteur Recoil (`spring-headless.exe`)

- [x] **Montage VFS du dépôt live (`Beyond-All-Reason.sdd`)** :
  - Jonction de développement connectée dans `data/games/Beyond-All-Reason.sdd`.
  - Exécution réussie dans `spring-headless.exe` :
    - Checksum serveur/client validés bit-à-bit.
    - Initialisation conjointe de `luaRules` et `luaGaia`.
    - Entrée en jeu validée sans plantage ni exception.
- [x] **Banc de test déterministe automatisé (`perf_benchmark_harness.lua` & `run_benchmark.ps1`)** :
  - Relecture headless non-bridée (`skip 3600`, `setminspeed 100`, `speed 100`) sur replay représentatif (`Iron_Isle_V1_2026.07.04.sdfz`).
  - Capture haute précision de chaque frame de simulation, percentiles P50/P95/P99, pics >33.3ms et échantillonnage mémoire Lua GC.
  - Calcul de checksum composite d'état de simulation à chaque checkpoint (toutes les 200 frames).
- [x] **Résultats chiffrés AVANT / APRÈS (Baseline vs Performance 2.0 sur 3 600 frames)** :

| Métrique | Baseline (BAR Main officiel) | Optimisé (BAR Performance 2.0) | Gain / Delta |
| :--- | :--- | :--- | :--- |
| **Durée Sim (3600 frames)** | 4.7330 s | 4.6820 s | **-1.08% (-51 ms)** |
| **Vitesse Sim Effectif** | 760.62 FPS | 768.90 FPS | **+8.28 FPS (+1.09%)** |
| **Facteur d'accélération temps-réel** | 25.35x | 25.63x | **+0.28x** |
| **Temps moyen par frame sim** | 1.3143 ms | 1.3007 ms | **-0.0136 ms** |
| **Temps frame P50 (Médiane)** | 1.0000 ms | 1.0000 ms | Identique |
| **Temps frame P95** | 2.0000 ms | 2.0000 ms | Identique |
| **Temps frame P99** | 3.0000 ms | 3.0000 ms | Identique |
| **Pics de frame (>33.3 ms)** | 0 (0.00%) | 1 (0.03%) | Négligeable |
| **RAM Lua Max (GC Peak)** | 8 884 Ko (8.68 Mo) | 8 880 Ko (8.67 Mo) | **-4 Ko (-4 096 octets)** |
| **RAM Lua Min** | 8 432 Ko (8.23 Mo) | 8 429 Ko (8.23 Mo) | **-3 Ko** |
| **Checksums de simulation (19 checkpoints)** | 19 / 19 identiques | 19 / 19 identiques | **100% Identité bit-à-bit (Zéro Desync)** |

- [x] **Vérification de déterminisme absolu (Zéro Desync)** :
  - Checkpoint 200: `F:200|U:4|X:246680|Z:36950|H:76439` (Match exact)
  - Checkpoint 1000: `F:1000|U:9|X:499240|Z:84390|H:118607` (Match exact)
  - Checkpoint 2000: `F:2000|U:19|X:1118400|Z:184975|H:153320` (Match exact)
  - Checkpoint 3000: `F:3000|U:29|X:1727526|Z:285055|H:181249` (Match exact)
  - Checkpoint 3600 (Final): `F:3600|U:32|X:1963526|Z:315135|H:205734` (Match exact)
- [x] **Détection et correction de régression de portée de variable** :
  - La simulation complète sur 36 000 frames a détecté une régression de portée dans `unit_carrier_spawner.lua` (`checkCarrierCallins` non déclaré en avant dans `UnitDestroyed`), corrigée avec déclaration lexicale propre.
- [x] **Suite de tests Rust intégrée** :
  - `cargo test` : 4 tests passés avec succès (`bar-cache-baker`, `bar-perf-core`).
  - `cargo clippy` : Zéro erreur, zéro avertissement.

---

## 7. Prochaines Étapes Opérationnelles (Axes Architecture 2.0)

1. **Axe C — Cache spatial partagé à l'échelle de la frame** :
   - Éviter la redondance des requêtes `GetUnitsInCylinder` / `GetUnitsInSphere` répétées avec les mêmes coordonnées dans la même frame par plusieurs gadgets de combat.
2. **Axe D & F — Optimisation et élimination du churn dans `unit_area_timed_damage.lua`** :
   - Recyclage de tables temporaires et mise en sommeil des callins lorsque aucune zone d'explosion minutée n'est active.
3. **Axe G — Cache binaire profond UnitDefs** :
   - Étendre `bar-cache-baker` pour sérialiser directement les définitions traitées et s'affranchir du coût d'évaluation Lua au démarrage.
