# Tournament Tracker — Repérage de paires de joueurs en tennis de table

Base de données conçue pour répondre à une question simple, posée souvent :
**parmi ces matchs à venir, lesquels m'intéressent ?**

Projet personnel, né d'un besoin réel. Un ami suit des tournois de tennis de table et reçoit
régulièrement, depuis une application, la liste des confrontations à venir. Seules certaines
paires de joueurs l'intéressent — celles qu'il a repérées au fil du temps. Il devait donc
parcourir chaque liste à la main pour voir si l'une de ses paires y figurait : long, répétitif,
et il en manquait.

La base stocke ses paires de référence. Il colle la liste des matchs à venir, et la requête
lui indique lesquels correspondent.

---

## Les données

| | |
|---|---|
| Joueurs | 228 |
| Paires suivies | 253 |

Les joueurs sont majoritairement ukrainiens, tchèques et slovaques.

## Le modèle

Deux tables :

- **`players`** — un joueur : prénom, nom.
- **`tracked_pairs`** — une paire de joueurs à repérer.

Et une vue, **`v_pairs`**, qui est la pièce centrale du projet (voir ci-dessous).

### Choix de conception

**Le modèle est volontairement minimal.** Ni vainqueur, ni score, ni date. La question posée
est de savoir si une paire fait partie de celles à repérer, rien de plus. Toute colonne
supplémentaire aurait alourdi la saisie sans servir le besoin.

**L'unicité porte sur le couple prénom + nom.** Une contrainte posée séparément sur chaque
colonne interdirait à deux joueurs de partager un prénom, ce qui est ingérable ici : 15 joueurs
s'appellent « Oleksandr », 15 « Serhii », 11 « Oleh ». La contrainte composée autorise ces cas
tout en empêchant deux fiches « Oleh Napirko ».

```sql
CONSTRAINT uq_player_name UNIQUE (first_name, last_name)
```

## Le problème central : une paire s'écrit dans les deux sens

Une paire Hura / Vlasenko peut être enregistrée comme `(Hura, Vlasenko)` ou comme
`(Vlasenko, Hura)`. C'est la même paire, mais une recherche naïve sur un seul sens en manque la
moitié — et la liste des matchs à venir ne respecte évidemment aucun ordre particulier. Dans ces
données, **11 paires apparaissent effectivement dans les deux sens**.

La vue `v_pairs` règle le problème en rangeant systématiquement les deux noms par ordre
alphabétique :

```sql
CREATE VIEW v_pairs AS
SELECT
    LEAST(   CONCAT(p1.first_name,' ',p1.last_name),
             CONCAT(p2.first_name,' ',p2.last_name)) AS player_a,
    GREATEST(CONCAT(p1.first_name,' ',p1.last_name),
             CONCAT(p2.first_name,' ',p2.last_name)) AS player_b
FROM tracked_pairs tp
JOIN players p1 ON p1.player_id = tp.player1_id
JOIN players p2 ON p2.player_id = tp.player2_id;
```

Chaque paire n'a donc plus qu'une seule écriture possible, des deux côtés de la comparaison.

Le même principe protège la saisie : une colonne générée `pair_key` range les deux
identifiants dans un ordre déterministe, et une contrainte `UNIQUE` porte sur elle. Une paire
déjà enregistrée est donc refusée même si on la saisit à l'envers.

## Utilisation

Le cas d'usage principal : coller la liste des matchs à venir et voir immédiatement lesquels
correspondent à une paire suivie.

```sql
WITH candidats (joueur_1, joueur_2) AS (
    SELECT 'Orest Hura',    'Valerii Vlasenko'
    UNION ALL SELECT 'Oleh Napirko', 'Mykyta Smyrnov'
)
SELECT c.joueur_1, c.joueur_2,
       CASE WHEN COUNT(v.pair_id) > 0
            THEN 'Paire suivie' ELSE '-' END AS statut
FROM candidats c
LEFT JOIN v_pairs v
       ON v.player_a = LEAST(   c.joueur_1, c.joueur_2)
      AND v.player_b = GREATEST(c.joueur_1, c.joueur_2)
GROUP BY c.joueur_1, c.joueur_2;
```

`queries.sql` contient huit requêtes commentées : vue d'ensemble, recherche d'une paire,
filtrage d'une liste de matchs à venir, partenaires d'un joueur donné, joueurs les plus
représentés, doublons, joueurs communs à deux paires, et contrôles qualité.

## Structure du dépôt

```
.
├── README.md
├── schema.sql                          # tables, contraintes, vue
├── seed_data.sql                       # 228 joueurs, 253 paires
├── queries.sql                         # 8 requêtes commentées
└── migrations/
    └── deduplicate_players.sql         # migration historique (documentation)
```

## Reproduire

```bash
mysql -u <utilisateur> -p < schema.sql
mysql -u <utilisateur> -p < seed_data.sql
```

Puis ouvrir `queries.sql` et exécuter les requêtes une par une.

Testé sur MySQL 8.

## Notes techniques

**Les joueurs sont désignés par leur nom, pas par un identifiant en dur.** Une première
version écrivait les matchs sous la forme `(1, 2), (5, 3)…`. Ces identifiants ne sont corrects
que si les joueurs ont été insérés exactement dans le même ordre : ajouter un joueur en amont
décale tout et fausse silencieusement les matchs. Chaque joueur est donc désigné par une
sous-requête sur son nom, ce qui rend le fichier robuste.

**Cinq paires ont été écartées** lors de la reprise des données : elles référençaient
des joueurs absents de la table (Danylo Us, Ivan Kryvyi, Mykola Treshchetka, Oleksandr Kolos,
Vadym Komar). Ces lignes auraient échoué à l'insertion, la contrainte `NOT NULL` rejetant le
résultat vide de la sous-requête. C'est un bon exemple de contrainte qui rend une erreur
visible au lieu de la laisser passer silencieusement.

**Le script de déduplication** (`migrations/`) documente la correction d'un problème rencontré
sur une version antérieure de la base, où le même joueur pouvait exister en double à cause des
variantes de translittération depuis l'ukrainien (Oleg / Oleh, Dmitriy / Dmytro). Il n'est plus
nécessaire, le schéma actuel empêchant ces doublons, mais il illustre la démarche : réaffecter
les clés étrangères avant de supprimer, dans un ordre qui ne viole aucune contrainte.

## Limites et suites possibles

- **La saisie reste manuelle.** Les listes de matchs à vérifier proviennent d'une application
  mobile, sous forme de captures d'écran, et doivent être retranscrites dans la requête.
  Une interface de saisie, ou un import depuis un fichier, supprimerait cette étape.
- **L'utilisateur final doit passer par un client SQL**, ce qui suppose de savoir s'en servir.
  Une petite interface web, ou même un formulaire, rendrait l'outil autonome.
- **Aucun résultat de match n'est stocké**, par choix : la base sert à repérer des paires, pas
  à analyser des performances. Si le besoin évoluait, une table dédiée aux rencontres réelles
  (avec date et vainqueur) viendrait s'ajouter, sans remplacer celle-ci.

## Technologies

MySQL 8 · SQL (DDL, contraintes, vues, CTE, jointures, agrégations)

## Auteure

Audrey Travant — [LinkedIn](https://www.linkedin.com/in/audrey-travant) · [GitHub](https://github.com/AudreyTravant)
