-- docker/configs/init-pii.sql
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    name TEXT,
    email TEXT,
    ssn TEXT
);
INSERT INTO users (name, email, ssn) VALUES
    ('Alice', 'alice@example.com', '111-22-3333'),
    ('Bob', 'bob@example.com', '444-55-6666');
