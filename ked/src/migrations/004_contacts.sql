-- ============================================================================
-- 004_contacts.sql — Contacts, Contact Interactions, and Notifications tables
-- ============================================================================

-- Contacts table: stores relationship cards extracted from voice notes
CREATE TABLE IF NOT EXISTS contacts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    company VARCHAR(255),
    role VARCHAR(255),
    email VARCHAR(255),
    phone VARCHAR(50),
    linkedin_url TEXT,
    event_name VARCHAR(255),
    event_date DATE,
    location VARCHAR(255),
    notes TEXT,
    interests JSONB DEFAULT '[]'::jsonb,
    opportunities JSONB DEFAULT '[]'::jsonb,
    summary TEXT,
    overlap_points JSONB DEFAULT '[]'::jsonb,
    overlap_score FLOAT DEFAULT 0.0,
    follow_up_draft TEXT,
    follow_up_sent BOOLEAN DEFAULT FALSE,
    follow_up_due TIMESTAMP WITH TIME ZONE,
    follow_up_completed BOOLEAN DEFAULT FALSE,
    relationship_strength INTEGER DEFAULT 1 CHECK (relationship_strength BETWEEN 1 AND 10),
    last_interaction_at TIMESTAMP WITH TIME ZONE,
    interaction_count INTEGER DEFAULT 1,
    source_type VARCHAR(50) DEFAULT 'voice_note',
    source_recording_id VARCHAR(255),
    is_starred BOOLEAN DEFAULT FALSE,
    tags JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Indexes for contacts
CREATE INDEX IF NOT EXISTS idx_contacts_user_id ON contacts(user_id);
CREATE INDEX IF NOT EXISTS idx_contacts_name ON contacts(user_id, name);
CREATE INDEX IF NOT EXISTS idx_contacts_event ON contacts(user_id, event_name);
CREATE INDEX IF NOT EXISTS idx_contacts_starred ON contacts(user_id, is_starred) WHERE is_starred = TRUE;
CREATE INDEX IF NOT EXISTS idx_contacts_follow_up ON contacts(user_id, follow_up_due) WHERE follow_up_completed = FALSE;
CREATE INDEX IF NOT EXISTS idx_contacts_strength ON contacts(user_id, relationship_strength);
CREATE INDEX IF NOT EXISTS idx_contacts_created ON contacts(user_id, created_at DESC);

-- Full-text search index for contacts
CREATE INDEX IF NOT EXISTS idx_contacts_fts ON contacts USING gin(
    to_tsvector('english', coalesce(name, '') || ' ' || coalesce(company, '') || ' ' || coalesce(role, '') || ' ' || coalesce(notes, '') || ' ' || coalesce(summary, ''))
);

-- Contact Interactions table: timeline of interactions with a contact
CREATE TABLE IF NOT EXISTS contact_interactions (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    contact_id INTEGER NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    interaction_type VARCHAR(50) NOT NULL DEFAULT 'initial_capture',
    content TEXT,
    recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contact_interactions_contact ON contact_interactions(contact_id);
CREATE INDEX IF NOT EXISTS idx_contact_interactions_user ON contact_interactions(user_id);

-- Notifications table: follow-up reminders and system notifications
CREATE TABLE IF NOT EXISTS notifications (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    type VARCHAR(50) NOT NULL DEFAULT 'follow_up_reminder',
    title VARCHAR(255) NOT NULL,
    body TEXT,
    read BOOLEAN DEFAULT FALSE,
    contact_id INTEGER REFERENCES contacts(id) ON DELETE SET NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON notifications(user_id, read) WHERE read = FALSE;

-- RLS Policies
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_isolation_contacts ON contacts;
CREATE POLICY user_isolation_contacts ON contacts
    USING (user_id = current_setting('app.current_user_id')::int);

ALTER TABLE contact_interactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_isolation_contact_interactions ON contact_interactions;
CREATE POLICY user_isolation_contact_interactions ON contact_interactions
    USING (user_id = current_setting('app.current_user_id')::int);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS user_isolation_notifications ON notifications;
CREATE POLICY user_isolation_notifications ON notifications
    USING (user_id = current_setting('app.current_user_id')::int);

-- Updated_at trigger for contacts
CREATE OR REPLACE FUNCTION update_modified_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

DROP TRIGGER IF EXISTS update_contacts_modtime ON contacts;
CREATE TRIGGER update_contacts_modtime
    BEFORE UPDATE ON contacts
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_column();
