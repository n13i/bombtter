CREATE TABLE bombs (
    status_id         INTEGER UNIQUE,
    target            TEXT,
    ctime             TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    posted_at         TIMESTAMP,
    source            INTEGER,
    result            INTEGER,
    -- added at 2009/10/11
    urgency           INTEGER NOT NULL DEFAULT 0,
    category          INTEGER NOT NULL DEFAULT 0,
    -- added at 2009/10/13
    target_normalized TEXT
);
CREATE TABLE buzz (
    id     INTEGER PRIMARY KEY,
    target TEXT,
    in_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    out_at TIMESTAMP
);
CREATE TABLE statuses (
    status_id    INTEGER UNIQUE,
    permalink    TEXT,
    screen_name  TEXT,
    name         TEXT,
    status_text  TEXT,
    ctime        TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    source       INTEGER,
    analyzed     INTEGER,
    is_protected INTEGER
);
