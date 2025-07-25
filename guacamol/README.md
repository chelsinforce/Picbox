1 : Git clone

2: 
```bash
curl -O https://raw.githubusercontent.com/apache/guacamole-client/1.6.0/extensions/guacamole-auth-jdbc/modules/guacamole-auth-jdbc-mysql/schema/001-create-schema.sql
```
3: docker-compose up -d

4: docker cp 001-create-schema.sql guac-mysql:/tmp/schema.sql

5: docker exec -it guac-mysql bash

6: mysql -u root -p

7: Entrez `some_root_password`

8: mysql> USE guacamole_db;

9: mysql> SOURCE /tmp/schema.sql;

10 : ajout de l'utilisateur de base

```mysql
-- Crée l'entité si pas encore faite
INSERT INTO guacamole_entity (name, type)
VALUES ('<your user>', 'USER');

-- Crée l'utilisateur avec le hash SHA-256 binaire (via UNHEX)
INSERT INTO guacamole_user (
    entity_id, password_hash, password_salt, password_date,
    disabled, expired, access_window_start, access_window_end,
    valid_from, valid_until
) VALUES (
    (SELECT entity_id FROM guacamole_entity WHERE name = '<your user>'),
    UNHEX('<hash password(echo -n '<your password>' | sha256sum)>'),
    NULL, NOW(),
    FALSE, FALSE, NULL, NULL, NULL, NULL
);

-- Donne les droits admin
INSERT INTO guacamole_system_permission (entity_id, permission)
SELECT entity_id, 'ADMINISTER'
FROM guacamole_entity
WHERE name = '<your user>';
```

11: Vérification

```mysql
SELECT * FROM guacamole_entity WHERE name = '<your user>';

SELECT * FROM guacamole_user WHERE entity_id = (
  SELECT entity_id FROM guacamole_entity WHERE name = '<your user>'
);

SELECT * FROM guacamole_system_permission WHERE entity_id = (
  SELECT entity_id FROM guacamole_entity WHERE name = '<your user>'
);

```
12: exit && exit
13 :  docker restart guacamole
14: http://votreIp:8080/guacamole/

