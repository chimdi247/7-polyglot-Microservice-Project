-- =============================================================================
-- 03-seed-admin-user.sql
--
-- Creates a login you can use immediately once the stack is up:
--   email:    admin@example.com
--   password: password123
--
-- The password is stored as a bcrypt hash (never plaintext), generated with
-- the same algorithm auth-service verifies against at login (Spring
-- Security's BCryptPasswordEncoder, strength 10).
--
-- This is separate from the app's own seeded demo account
-- (admin@devopsshack.com / admin123, created by auth-service itself on
-- first boot) — both will exist side by side.
--
-- Change this password (or remove this user) before using this anywhere
-- other than local development.
-- =============================================================================

\c auth_db

INSERT INTO app_users (name, email, password_hash, role)
SELECT
    'Admin User',
    'admin@example.com',
    '$2b$10$Cjt4J8.rZagjuVg09yC61uVVfsqBEZrNpYBeHjJW4X7yeu5XngPCq',
    'ADMIN'
WHERE NOT EXISTS (
    SELECT 1 FROM app_users WHERE email = 'admin@example.com'
);
