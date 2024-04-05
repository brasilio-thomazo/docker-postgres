-- This is an example of an init script that creates a table and inserts a row into it
-- place it in /entrypoint.d/ to have it run when the container starts

-- Create the database if it doesn't exist
SELECT 'CREATE DATABSE db_test' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'db_test');
-- Connect to the database
\c db_test;

-- Create the table if it doesn't exist
CREATE TABLE IF NOT EXISTS posts (
  id SERIAL PRIMARY KEY,
  title TEXT NOT NULL,
  body TEXT NOT NULL
);

-- Insert a row into the table  
INSERT INTO posts (title, body) VALUES ('Hello', 'Hello, world!');

-- Select all rows from the table
SELECT * FROM posts;