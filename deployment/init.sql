CREATE SCHEMA IF NOT EXISTS public;
GRANT ALL ON SCHEMA public TO postgres;
GRANT ALL ON SCHEMA public TO public;

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS postgis;

CREATE ROLE data_collector;

----------------------- user management -------------------------
CREATE TABLE IF NOT EXISTS users
(
    user_id UUID PRIMARY KEY,
    email TEXT NOT NULL UNIQUE,
    password TEXT,
    is_verified BOOLEAN NOT NULL DEFAULT TRUE
);

INSERT INTO users (user_id, email) VALUES ('00000000-0000-0000-0000-000000000001', 'sentinel@commonspace.sidewalklabs.com');

CREATE UNIQUE INDEX users_lower_email_unique_idx ON users (lower(email));

CREATE TABLE IF NOT EXISTS password_reset
(
    email TEXT UNIQUE REFERENCES public.users(email) ON DELETE CASCADE,
    token TEXT PRIMARY KEY,
    expiration TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS account_verification
(
    user_id UUID UNIQUE NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
    token TEXT PRIMARY KEY,
    expiration TIMESTAMP WITH TIME ZONE
);

CREATE TABLE IF NOT EXISTS admin_whitelist
(
    email TEXT PRIMARY KEY
);

CREATE TABLE IF NOT EXISTS token_blacklist
(
    token TEXT PRIMARY KEY,
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    blacklisted_at TIMESTAMP WITH TIME ZONE default now()
);

--------------------------- data collection ---------------------------

CREATE SCHEMA IF NOT EXISTS data_collection;
ALTER ROLE data_collector SET search_path TO data_collection,"$user",public;
-- ALTER ROLE <your_login_role> SET search_path TO data_collection,"$user",public;
SET search_path TO data_collection;

CREATE TYPE studyScale AS ENUM ('district', 'city', 'cityCentre', 'neighborhood', 'blockScale', 'singleSite');
CREATE TYPE studyType AS ENUM('stationary', 'movement');


CREATE TABLE IF NOT EXISTS location
(
    location_id UUID PRIMARY KEY,
    country TEXT,
    city TEXT,
    name_primary TEXT,
    subdivision TEXT,
    geometry public.geometry
);

CREATE TYPE studyStatus AS ENUM ('completed', 'active');

CREATE TABLE IF NOT EXISTS study
(
    study_id UUID PRIMARY KEY,
    title TEXT,
    status studyStatus DEFAULT 'active',
    author TEXT,
    author_url TEXT,
    project TEXT,
    project_phase TEXT,
    state_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE,
    scale studyScale,
    is_public BOOLEAN DEFAULT FALSE,
    user_id UUID REFERENCES public.users(user_id) NOT NULL,
    protocol_version TEXT NOT NULL,
    study_type studyType NOT NULL,
    fields VARCHAR[],
    tablename VARCHAR(63),
    location TEXT,
    map JSON,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT now(),
    last_updated TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE TYPE gender AS ENUM (
        'male',
        'female',
        'unknown');
CREATE TYPE age AS ENUM (
       '0-14',
       '15-24',
       '25-64',
       '65+');
CREATE TYPE mode AS ENUM (
       'pedestrian',
       'bicyclist',
       'other');
CREATE TYPE posture AS ENUM (
       'leaning',
       'lying',
       'sitting',
       'sitting on the ground',
       'standing',
       'sitting_informal',
       'sitting_formal');

CREATE TYPE activities AS ENUM (
       'commercial',
       'consuming',
       'conversing',
       'cultural',
       'disruptive',
       'electronic_engagement',
       'living_public',
       'pets',
       'idle',
       'running',
       'recreation_active',
       'recreation_passive',
       'smoking',
       'soliciting',
       'waiting_transfer',
       'waiting_other',
       'working_civic'
);
CREATE TYPE groups AS ENUM (
       'group_1',
       'group_2',
       'group_3-7',
       'group_8+');
CREATE TYPE object AS ENUM (
       'animal',
       'bag_carried',
       'clothing_cultural',
       'clothing_activity',
       'goods_carried',
       'equipment_construction',
       'equipment_receational',
       'equipment_sport',
       'protection_safety',
       'protection_weather',
       'furniture_carried',
       'transportation_carried',
       'transportation_stationary',
       'pushcart',
       'stroller',
       'luggage');

CREATE TABLE IF NOT EXISTS surveyors (
    user_id UUID references public.users(user_id) ON DELETE CASCADE NOT NULL,
    study_id UUID references study(study_id) ON DELETE CASCADE NOT NULL,
    PRIMARY KEY(study_id, user_id)
);

-- survey metadata
--  no user tied to this? I guess anonymous surveys are a thing, what about fake data?
-- TODO should id have default uuid function call?
CREATE TABLE IF NOT EXISTS survey (
    study_id UUID references study(study_id) ON DELETE CASCADE NOT NULL,
    title TEXT,
    location_id UUID,
    survey_id UUID PRIMARY KEY,
    start_date TIMESTAMP WITH TIME ZONE,
    end_date TIMESTAMP WITH TIME ZONE,
    time_character TEXT,
    representation TEXT NOT NULL,
    microclimate TEXT,
    temperature_c FLOAT,
    method TEXT NOT NULL,
    user_id UUID references public.users(user_id),
    --FOREIGN KEY (study_id, user_id) references surveyors (study_id, user_id),
    notes TEXT
);


CREATE OR REPLACE VIEW survey_to_tablename AS
 SELECT sr.survey_id, st.tablename
 FROM study as st
 INNER JOIN survey as sr
 ON st.study_id = sr.study_id;

DROP FUNCTION IF EXISTS get_datapoints_across_studies();

CREATE OR REPLACE FUNCTION get_datapoints_across_studies()
	RETURNS TABLE (data_point_id UUID) AS $$
DECLARE
    table_name text;
    retval uuid;
BEGIN
    DROP TABLE IF EXISTS tmptable;
    CREATE TEMPORARY TABLE IF NOT EXISTS tmptable (data_point_id UUID );
	
    FOR table_name IN
		SELECT tablename from data_collection.study
	LOOP
		EXECUTE format('insert into tmptable select data_point_id from %s', table_name);
	END LOOP;

    RETURN QUERY
        SELECT * FROM tmptable;
END;
$$
LANGUAGE PLPGSQL;
