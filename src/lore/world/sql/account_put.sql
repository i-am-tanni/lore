INSERT INTO account (name, password_hash, role)
VALUES ($1, $2,
  CASE
    WHEN (SELECT 1 FROM account WHERE role = 'admin'::role_enum LIMIT 1) IS NULL
      THEN 'admin'::role_enum
  ELSE
    'user'::role_enum
  END
);
