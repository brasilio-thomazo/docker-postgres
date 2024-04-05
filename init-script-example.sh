#!/bin/bash

# This is an example of an init script that creates a table and inserts a row into it
# place it in /entrypoint.d/ to have it run when the container starts

psql -v -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
    -- create a new database
    CREATE DATABASE db_test;
     -- switch to the new database
    \c db_test;
EOSQL

psql -v -U "$POSTGRES_USER" -d "$POSTGRES_DB" <<-EOSQL
    -- create a new table
    CREATE TABLE IF NOT EXISTS users (
        id SERIAL PRIMARY KEY,
        name VARCHAR(100) NOT NULL,
        email VARCHAR(100) NOT NULL
    );

    -- insert a row into the table
    INSERT INTO users (name, email) VALUES ('John Doe', 'john.doe@example.com');

    -- select all rows from the table
    SELECT * FROM users;
EOSQL
