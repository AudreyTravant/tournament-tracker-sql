-- =============================================================
--  Tournament Tracker — Schéma de la base
--  Repérage de paires de joueurs de tennis de table
-- =============================================================
--  À exécuter en premier, avant seed_data.sql.
--  Testé sur MySQL 8.
-- =============================================================

CREATE SCHEMA IF NOT EXISTS tournament_tracker;
USE tournament_tracker;

-- L'ordre des suppressions est important : tracked_pairs référence
-- players par clé étrangère, il faut donc la supprimer en premier.
DROP VIEW  IF EXISTS v_pairs;
DROP TABLE IF EXISTS tracked_pairs;
DROP TABLE IF EXISTS players;


-- -------------------------------------------------------------
--  Table players
-- -------------------------------------------------------------
CREATE TABLE players (
    player_id  INT PRIMARY KEY AUTO_INCREMENT,
    first_name VARCHAR(100) NOT NULL,
    last_name  VARCHAR(100) NOT NULL,

    -- La contrainte porte sur le COUPLE prénom + nom, et non sur chaque
    -- colonne séparément. Deux joueurs peuvent donc se prénommer "Oleh",
    -- mais il ne peut exister qu'un seul "Oleh Napirko".
    CONSTRAINT uq_player_name UNIQUE (first_name, last_name)
);


-- -------------------------------------------------------------
--  Table tracked_pairs
-- -------------------------------------------------------------
--  Une ligne = une paire de joueurs à repérer dans les listes de
--  matchs à venir.
--
--  Sur l'ordre des joueurs : une paire peut être saisie dans un sens
--  ou dans l'autre. Plutôt que d'imposer un ordre à la saisie, la
--  colonne générée pair_key range les deux identifiants de façon
--  déterministe (le plus petit d'abord). L'unicité porte sur cette
--  clé : (12, 45) et (45, 12) sont donc reconnues comme la même paire
--  et ne peuvent pas coexister.
-- -------------------------------------------------------------
CREATE TABLE tracked_pairs (
    pair_id    INT PRIMARY KEY AUTO_INCREMENT,
    player1_id INT NOT NULL,
    player2_id INT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,

    -- Clé normalisée : "petit_id-grand_id", quel que soit l'ordre de saisie.
    pair_key VARCHAR(25) AS (
        CONCAT(LEAST(player1_id, player2_id), '-', GREATEST(player1_id, player2_id))
    ) STORED,

    CONSTRAINT fk_pairs_p1 FOREIGN KEY (player1_id) REFERENCES players(player_id),
    CONSTRAINT fk_pairs_p2 FOREIGN KEY (player2_id) REFERENCES players(player_id),

    -- Un joueur ne peut pas former une paire avec lui-même.
    CONSTRAINT chk_no_self_pair CHECK (player1_id <> player2_id),

    -- Empêche d'enregistrer deux fois la même paire, y compris inversée.
    CONSTRAINT uq_pair UNIQUE (pair_key)
);


-- -------------------------------------------------------------
--  Vue v_pairs — le cœur du projet
-- -------------------------------------------------------------
--  Problème : une paire Hura / Vlasenko peut avoir été saisie comme
--  (Hura, Vlasenko) ou comme (Vlasenko, Hura), et la liste des matchs
--  à venir ne respecte évidemment aucun ordre particulier. Une
--  comparaison naïve sur un seul sens en manquerait la moitié.
--
--  Solution : LEAST et GREATEST rangent toujours les deux noms dans
--  le même ordre alphabétique. Chaque paire a donc une seule écriture
--  possible, et la comparaison devient fiable quel que soit le sens
--  de saisie, des deux côtés.
-- -------------------------------------------------------------
CREATE VIEW v_pairs AS
SELECT
    tp.pair_id,
    LEAST(   CONCAT(p1.first_name,' ',p1.last_name),
             CONCAT(p2.first_name,' ',p2.last_name)) AS player_a,
    GREATEST(CONCAT(p1.first_name,' ',p1.last_name),
             CONCAT(p2.first_name,' ',p2.last_name)) AS player_b
FROM tracked_pairs tp
JOIN players p1 ON p1.player_id = tp.player1_id
JOIN players p2 ON p2.player_id = tp.player2_id;
