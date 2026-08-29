-- =============================================================
--  Migration historique — Fusion des joueurs en double
-- =============================================================
--  CE SCRIPT N'EST PLUS À EXÉCUTER. Il est conservé à titre de
--  documentation.
--
--  CONTEXTE
--  --------
--  Dans les premières versions de la base, la contrainte d'unicité
--  était posée séparément sur first_name et sur last_name. Elle était
--  à la fois trop stricte (deux joueurs ne pouvaient pas partager un
--  prénom, alors que 15 d'entre eux s'appellent "Oleksandr") et
--  inefficace pour empêcher les vrais doublons.
--
--  Résultat : le même joueur pouvait être saisi deux fois, souvent à
--  cause des variantes de translittération depuis l'ukrainien
--  (Oleg / Oleh, Dmitriy / Dmytro, Pismenniy / Pysmennyi).
--
--  Ces doublons ne pouvaient pas être supprimés directement : des
--  paires pointaient déjà vers les deux identifiants. Il fallait donc
--  d'abord réaffecter les paires, puis supprimer.
--
--  Le schéma actuel (voir schema.sql) pose la contrainte sur le COUPLE
--  (first_name, last_name), ce qui empêche ces doublons d'apparaître.
--
--  ORDRE DES OPÉRATIONS
--  --------------------
--  1. Repérer les doublons
--  2. Construire la table de correspondance (identifiant conservé / supprimé)
--  3. Supprimer les paires qui associeraient un joueur à lui-même après fusion
--  4. Réaffecter les paires restantes vers l'identifiant conservé
--  5. Supprimer les lignes en double
--
--  L'étape 3 est indispensable : sans elle, une paire formée des deux
--  fiches d'un même joueur deviendrait, après réaffectation, une paire
--  d'un joueur avec lui-même — ce que la contrainte chk_no_self_pair
--  rejette.
-- =============================================================

USE tournament_tracker;


-- -------------------------------------------------------------
--  Étape 1 — Repérer les doublons
-- -------------------------------------------------------------
SELECT
    first_name,
    last_name,
    COUNT(*) AS occurrences
FROM players
GROUP BY first_name, last_name
HAVING COUNT(*) > 1;


-- -------------------------------------------------------------
--  Étape 2 — Table de correspondance
-- -------------------------------------------------------------
--  Pour chaque doublon : on garde le plus petit identifiant (le plus
--  ancien) et on supprimera le plus grand.
-- -------------------------------------------------------------
CREATE TEMPORARY TABLE duplicate_mapping AS
SELECT
    MIN(player_id) AS keep_id,
    MAX(player_id) AS delete_id
FROM players
GROUP BY first_name, last_name
HAVING COUNT(*) > 1;

SELECT * FROM duplicate_mapping;


-- -------------------------------------------------------------
--  Étape 3 — Supprimer les paires qui deviendraient invalides
-- -------------------------------------------------------------
--  Cas d'une paire formée des deux fiches du même joueur : après
--  fusion elle associerait le joueur à lui-même. On la supprime.
-- -------------------------------------------------------------
DELETE m FROM tracked_pairs m
JOIN duplicate_mapping dm
  ON (m.player1_id = dm.keep_id   AND m.player2_id = dm.delete_id)
  OR (m.player1_id = dm.delete_id AND m.player2_id = dm.keep_id);


-- -------------------------------------------------------------
--  Étape 4 — Réaffecter les paires restantes
-- -------------------------------------------------------------
--  Les deux colonnes de joueur sont traitées séparément : un doublon
--  peut apparaître aussi bien en player1 qu'en player2.
-- -------------------------------------------------------------
UPDATE tracked_pairs m
JOIN duplicate_mapping dm ON m.player1_id = dm.delete_id
SET m.player1_id = dm.keep_id;

UPDATE tracked_pairs m
JOIN duplicate_mapping dm ON m.player2_id = dm.delete_id
SET m.player2_id = dm.keep_id;


-- -------------------------------------------------------------
--  Étape 5 — Supprimer les fiches en double
-- -------------------------------------------------------------
--  Plus aucune paire ne les référence : la suppression ne viole
--  aucune clé étrangère.
-- -------------------------------------------------------------
DELETE FROM players
WHERE player_id IN (SELECT delete_id FROM duplicate_mapping);


-- -------------------------------------------------------------
--  Vérification
-- -------------------------------------------------------------
SELECT COUNT(*) AS doublons_restants
FROM (
    SELECT first_name, last_name
    FROM players
    GROUP BY first_name, last_name
    HAVING COUNT(*) > 1
) AS t;
