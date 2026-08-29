-- =============================================================
--  Tournament Tracker — Requêtes
-- =============================================================
--  Chaque requête répond à une question concrète, indiquée en
--  commentaire. Les noms entre guillemets sont à remplacer.
-- =============================================================

USE tournament_tracker;


-- -------------------------------------------------------------
--  1. Vue d'ensemble : combien de joueurs, combien de paires ?
-- -------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM players)       AS nb_joueurs,
    (SELECT COUNT(*) FROM tracked_pairs) AS nb_paires_suivies,
    ROUND((SELECT COUNT(*) FROM tracked_pairs) * 2.0
          / (SELECT COUNT(*) FROM players), 1) AS moyenne_paires_par_joueur;


-- -------------------------------------------------------------
--  2. Cette paire fait-elle partie des paires suivies ?
-- -------------------------------------------------------------
--  La vue v_pairs range les deux noms par ordre alphabétique, donc
--  l'ordre de saisie n'a aucune importance : chercher "Hura / Vlasenko"
--  ou "Vlasenko / Hura" donne le même résultat.
-- -------------------------------------------------------------
SELECT
    CASE WHEN COUNT(*) > 0 THEN 'Paire suivie' ELSE 'Non suivie' END AS statut
FROM v_pairs
WHERE player_a = LEAST(   'Orest Hura', 'Valerii Vlasenko')
  AND player_b = GREATEST('Orest Hura', 'Valerii Vlasenko');


-- -------------------------------------------------------------
--  3. Filtrer une liste de matchs à venir  ***REQUÊTE PRINCIPALE***
-- -------------------------------------------------------------
--  Le cas d'usage réel : une liste de confrontations à venir arrive
--  depuis l'application, il faut repérer celles qui correspondent à
--  une paire suivie — sans avoir à parcourir la liste à la main.
--
--  Pour l'utiliser : remplacer les lignes de la partie "a_venir" par
--  la liste du jour. Le reste ne bouge pas. L'ordre des deux joueurs
--  dans la liste n'a aucune importance.
-- -------------------------------------------------------------
WITH a_venir (joueur_1, joueur_2) AS (
              SELECT 'Orest Hura',        'Valerii Vlasenko'   -- ← remplacer
    UNION ALL SELECT 'Oleh Napirko',      'Mykyta Smyrnov'     --    par la liste
    UNION ALL SELECT 'Premysl Rucky',     'Tomas Hucko'        --    du jour
    UNION ALL SELECT 'Denys Maltsev',     'Serhii Prus'
    UNION ALL SELECT 'Dmytro Prylepa',    'Bogdan Panchenko'
)
SELECT
    a.joueur_1,
    a.joueur_2,
    CASE WHEN v.pair_id IS NOT NULL THEN 'Paire suivie' ELSE '-' END AS statut
FROM a_venir a
LEFT JOIN v_pairs v
       ON v.player_a = LEAST(   a.joueur_1, a.joueur_2)
      AND v.player_b = GREATEST(a.joueur_1, a.joueur_2)
ORDER BY (v.pair_id IS NULL), a.joueur_1;


-- -------------------------------------------------------------
--  4. Ne garder que les matchs qui m'intéressent
-- -------------------------------------------------------------
--  Variante de la requête 3 : au lieu d'annoter toute la liste, on
--  n'affiche que les correspondances. Plus court quand la liste est
--  longue et que seules quelques paires ressortent.
-- -------------------------------------------------------------
WITH a_venir (joueur_1, joueur_2) AS (
              SELECT 'Orest Hura',     'Valerii Vlasenko'
    UNION ALL SELECT 'Oleh Napirko',   'Mykyta Smyrnov'
    UNION ALL SELECT 'Premysl Rucky',  'Tomas Hucko'
)
SELECT a.joueur_1, a.joueur_2
FROM a_venir a
JOIN v_pairs v
  ON v.player_a = LEAST(   a.joueur_1, a.joueur_2)
 AND v.player_b = GREATEST(a.joueur_1, a.joueur_2);


-- -------------------------------------------------------------
--  5. Avec qui ce joueur est-il apparié ?
-- -------------------------------------------------------------
--  Le joueur cherché peut être enregistré en player1 comme en player2 :
--  la clause WHERE teste donc les deux colonnes, et le CASE renvoie
--  l'autre joueur de la paire, quel que soit le sens de la saisie.
-- -------------------------------------------------------------
SELECT
    CASE WHEN p1.last_name = 'Hura'
         THEN CONCAT(p2.first_name, ' ', p2.last_name)
         ELSE CONCAT(p1.first_name, ' ', p1.last_name)
    END AS autre_joueur
FROM tracked_pairs tp
JOIN players p1 ON p1.player_id = tp.player1_id
JOIN players p2 ON p2.player_id = tp.player2_id
WHERE p1.last_name = 'Hura' OR p2.last_name = 'Hura'
ORDER BY autre_joueur;


-- -------------------------------------------------------------
--  6. Quels joueurs reviennent le plus souvent ?
-- -------------------------------------------------------------
--  Un joueur compte une paire qu'il figure en player1 ou en player2 :
--  on empile donc les deux colonnes avec UNION ALL avant de compter.
-- -------------------------------------------------------------
SELECT
    CONCAT(p.first_name, ' ', p.last_name) AS joueur,
    COUNT(*) AS nb_paires
FROM (
    SELECT player1_id AS player_id FROM tracked_pairs
    UNION ALL
    SELECT player2_id FROM tracked_pairs
) AS participations
JOIN players p ON p.player_id = participations.player_id
GROUP BY p.player_id, joueur
ORDER BY nb_paires DESC, joueur
LIMIT 20;


-- -------------------------------------------------------------
--  7. Deux joueurs ont-ils des partenaires de paire en commun ?
-- -------------------------------------------------------------
WITH partenaires AS (
    SELECT player_a AS joueur, player_b AS partenaire FROM v_pairs
    UNION
    SELECT player_b, player_a FROM v_pairs
)
SELECT a1.partenaire AS partenaire_commun
FROM partenaires a1
JOIN partenaires a2 ON a1.partenaire = a2.partenaire
WHERE a1.joueur = 'Orest Hura'
  AND a2.joueur = 'Valerii Vlasenko'
ORDER BY partenaire_commun;


-- -------------------------------------------------------------
--  8. Contrôle qualité : la base est-elle saine ?
-- -------------------------------------------------------------
--  Les quatre compteurs doivent tous valoir 0.
--  Le dernier est en principe impossible grâce à la contrainte
--  uq_pair, mais le vérifier reste utile après un import.
-- -------------------------------------------------------------
SELECT 'Joueurs en double (même prénom + nom)' AS controle,
       COUNT(*) AS nb
FROM (SELECT first_name, last_name FROM players
      GROUP BY first_name, last_name HAVING COUNT(*) > 1) AS t

UNION ALL
SELECT 'Paires d''un joueur avec lui-même',
       COUNT(*) FROM tracked_pairs WHERE player1_id = player2_id

UNION ALL
SELECT 'Paires référençant un joueur inexistant',
       COUNT(*) FROM tracked_pairs tp
       LEFT JOIN players p1 ON p1.player_id = tp.player1_id
       LEFT JOIN players p2 ON p2.player_id = tp.player2_id
       WHERE p1.player_id IS NULL OR p2.player_id IS NULL

UNION ALL
SELECT 'Paires en double (y compris inversées)',
       COUNT(*) FROM (SELECT player_a, player_b FROM v_pairs
                      GROUP BY player_a, player_b HAVING COUNT(*) > 1) AS t2;
