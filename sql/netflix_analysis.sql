-- ============================================================
-- Netflix Content Strategy Analysis
-- Tool: PostgreSQL (pgAdmin4)
-- Author: Misba Khatoon
-- Description: 13 business-driven SQL queries analysing Netflix
--              content strategy across growth, geography,
--              audience targeting, format, and talent.
-- ============================================================


-- ============================================================
-- SCHEMA
-- ============================================================

DROP TABLE IF EXISTS netflix;

CREATE TABLE netflix (
    show_id      VARCHAR(6),
    type         VARCHAR(10),
    title        VARCHAR(150),
    director     VARCHAR(208),
    casts        VARCHAR(1000),
    country      VARCHAR(150),
    date_added   VARCHAR(50),
    release_year INT,
    rating       VARCHAR(10),
    duration     VARCHAR(15),
    listed_in    VARCHAR(100),
    description  VARCHAR(250)
);


-- ============================================================
-- IMPORT DATA
-- ============================================================

-- Update the file path below to match your local machine
COPY netflix
FROM 'YOUR_PATH\netflix_titles.csv'
DELIMITER ','
CSV HEADER;


-- ============================================================
-- DATA INSPECTION
-- ============================================================

-- Total row count
SELECT COUNT(*) AS total_rows FROM netflix;

-- Confirm only valid content types exist
SELECT DISTINCT type FROM netflix;

-- Check for duplicate show_id
SELECT show_id, COUNT(*)
FROM netflix
GROUP BY show_id
HAVING COUNT(*) > 1;

-- Missing values per column
SELECT
    COUNT(*) FILTER (WHERE type IS NULL)        AS missing_type,
    COUNT(*) FILTER (WHERE title IS NULL)       AS missing_title,
    COUNT(*) FILTER (WHERE director IS NULL)    AS missing_director,
    COUNT(*) FILTER (WHERE casts IS NULL)       AS missing_casts,
    COUNT(*) FILTER (WHERE country IS NULL)     AS missing_country,
    COUNT(*) FILTER (WHERE date_added IS NULL)  AS missing_date_added,
    COUNT(*) FILTER (WHERE rating IS NULL)      AS missing_rating,
    COUNT(*) FILTER (WHERE duration IS NULL)    AS missing_duration
FROM netflix;

-- Check all unique rating values (reveals dirty values)
SELECT DISTINCT rating, COUNT(*) AS count
FROM netflix
GROUP BY rating
ORDER BY count DESC;


-- ============================================================
-- SECTION 1: CONTENT MIX & GROWTH
-- ============================================================

-- Q1: How has the Movies vs TV Shows mix changed year over year?
-- Reveals whether Netflix is shifting strategy toward series or films
SELECT
    EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY')) AS year_added,
    type,
    COUNT(*) AS total_titles
FROM netflix
WHERE date_added IS NOT NULL
GROUP BY year_added, type
ORDER BY year_added, type;


-- Q2: Which genres have grown fastest in the last 3 years, and which are shrinking?
-- Identifies where Netflix is actively investing vs deprioritising
WITH genre_data AS (
    SELECT
        unnest(string_to_array(listed_in, ',')) AS genre,
        EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY')) AS year_added
    FROM netflix
    WHERE date_added IS NOT NULL
),
genre_period AS (
    SELECT
        TRIM(genre) AS genre,
        COUNT(*) FILTER (WHERE year_added >= 2019) AS recent_3yr,
        COUNT(*) FILTER (WHERE year_added < 2019)  AS prior_years
    FROM genre_data
    GROUP BY TRIM(genre)
)
SELECT
    genre,
    recent_3yr,
    prior_years,
    recent_3yr - prior_years AS growth_diff,
    ROUND(
        (recent_3yr::NUMERIC - prior_years) / NULLIF(prior_years, 0) * 100, 2
    ) AS growth_pct
FROM genre_period
ORDER BY growth_pct DESC NULLS LAST;


-- Q3: What is the average gap between a title's release year and when it was added to Netflix?
-- Indicates licensing speed and content acquisition strategy over time
WITH gap_data AS (
    SELECT
        EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY')) AS year_added,
        release_year,
        EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY')) - release_year AS gap_years
    FROM netflix
    WHERE date_added IS NOT NULL
)
SELECT
    year_added,
    ROUND(AVG(gap_years), 2)  AS avg_gap_years,
    MIN(gap_years)             AS min_gap,
    MAX(gap_years)             AS max_gap,
    COUNT(*)                   AS total_titles
FROM gap_data
WHERE gap_years >= 0
GROUP BY year_added
ORDER BY year_added;


-- ============================================================
-- SECTION 2: GEOGRAPHIC STRATEGY
-- ============================================================

-- Q4: Top 5 content-producing countries and their dominant genre each
-- Shows how Netflix localises content differently by market
WITH country_split AS (
    SELECT
        show_id,
        TRIM(unnest(string_to_array(country, ','))) AS country_name
    FROM netflix
    WHERE country IS NOT NULL
),
genre_split AS (
    SELECT
        show_id,
        TRIM(unnest(string_to_array(listed_in, ','))) AS genre
    FROM netflix
    WHERE listed_in IS NOT NULL
),
country_data AS (
    SELECT cs.country_name, gs.genre
    FROM country_split cs
    INNER JOIN genre_split gs ON cs.show_id = gs.show_id
),
top_countries AS (
    SELECT country_name, COUNT(*) AS total_content
    FROM country_split
    GROUP BY country_name
    ORDER BY total_content DESC
    LIMIT 5
),
country_genre_rank AS (
    SELECT
        cd.country_name,
        cd.genre,
        COUNT(*) AS genre_count,
        RANK() OVER (PARTITION BY cd.country_name ORDER BY COUNT(*) DESC) AS genre_rank
    FROM country_data cd
    INNER JOIN top_countries tc ON cd.country_name = tc.country_name
    GROUP BY cd.country_name, cd.genre
)
SELECT
    tc.country_name,
    tc.total_content,
    cgr.genre  AS dominant_genre,
    cgr.genre_count
FROM top_countries tc
INNER JOIN country_genre_rank cgr ON tc.country_name = cgr.country_name
WHERE cgr.genre_rank = 1
ORDER BY tc.total_content DESC;


-- Q5: How does India's genre mix compare to the US?
-- Direct market comparison revealing content diversification differences
WITH country_split AS (
    SELECT
        show_id,
        TRIM(unnest(string_to_array(country, ','))) AS country_name
    FROM netflix
    WHERE country IS NOT NULL
),
genre_split AS (
    SELECT
        show_id,
        TRIM(unnest(string_to_array(listed_in, ','))) AS genre
    FROM netflix
    WHERE listed_in IS NOT NULL
),
country_genre AS (
    SELECT cs.country_name, gs.genre
    FROM country_split cs
    INNER JOIN genre_split gs ON cs.show_id = gs.show_id
    WHERE cs.country_name IN ('India', 'United States')
),
genre_counts AS (
    SELECT
        country_name,
        genre,
        COUNT(*) AS genre_count,
        SUM(COUNT(*)) OVER (PARTITION BY country_name) AS country_total
    FROM country_genre
    GROUP BY country_name, genre
)
SELECT
    country_name,
    genre,
    genre_count,
    ROUND(genre_count::NUMERIC / country_total * 100, 2) AS pct_of_country_content
FROM genre_counts
ORDER BY country_name, genre_count DESC;


-- Q6: Which countries have shown the fastest growth in content output?
-- Flags emerging markets where Netflix is scaling investment
WITH country_split AS (
    SELECT
        show_id,
        TRIM(unnest(string_to_array(country, ','))) AS country_name
    FROM netflix
    WHERE country IS NOT NULL
),
country_year AS (
    SELECT
        cs.country_name,
        EXTRACT(YEAR FROM TO_DATE(n.date_added, 'Month DD, YYYY')) AS year_added
    FROM country_split cs
    INNER JOIN netflix n ON cs.show_id = n.show_id
    WHERE n.date_added IS NOT NULL
),
country_period AS (
    SELECT
        country_name,
        COUNT(*) FILTER (WHERE year_added >= 2019) AS recent_3yr,
        COUNT(*) FILTER (WHERE year_added < 2019)  AS prior_years
    FROM country_year
    GROUP BY country_name
)
SELECT
    country_name,
    recent_3yr,
    prior_years,
    recent_3yr - prior_years AS growth_diff,
    ROUND(
        (recent_3yr::NUMERIC - prior_years) / NULLIF(prior_years, 0) * 100, 2
    ) AS growth_pct
FROM country_period
WHERE prior_years >= 20
ORDER BY growth_pct DESC NULLS LAST
LIMIT 15;


-- ============================================================
-- SECTION 3: AUDIENCE & RATING STRATEGY
-- ============================================================

-- Q7: How has the distribution of content ratings shifted over the years?
-- Reveals whether Netflix's audience targeting is skewing mature or family
WITH rating_year AS (
    SELECT
        rating,
        EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY')) AS year_added,
        COUNT(*) AS title_count,
        SUM(COUNT(*)) OVER (
            PARTITION BY EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY'))
        ) AS yearly_total
    FROM netflix
    WHERE date_added IS NOT NULL
    AND rating IS NOT NULL
    AND rating NOT IN ('74 min', '84 min', '66 min')
    AND EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY')) >= 2015
    GROUP BY rating,
             EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY'))
)
SELECT
    year_added,
    rating,
    title_count,
    ROUND(title_count::NUMERIC / yearly_total * 100, 2) AS pct_of_year
FROM rating_year
ORDER BY year_added, pct_of_year DESC;


-- Q8: Which genres skew toward mature vs family-friendly ratings?
-- Helps understand content positioning and audience targeting by genre
WITH genre_split AS (
    SELECT
        show_id,
        TRIM(unnest(string_to_array(listed_in, ','))) AS genre
    FROM netflix
    WHERE listed_in IS NOT NULL
),
genre_rating AS (
    SELECT
        gs.genre,
        CASE
            WHEN n.rating IN ('TV-MA', 'R', 'NC-17', 'UR', 'NR') THEN 'Mature'
            WHEN n.rating IN ('TV-14', 'PG-13')                   THEN 'Teen'
            WHEN n.rating IN ('TV-G', 'TV-Y', 'TV-Y7',
                              'TV-Y7-FV', 'G', 'PG', 'TV-PG')    THEN 'Family'
            ELSE NULL
        END AS audience_category
    FROM genre_split gs
    INNER JOIN netflix n ON gs.show_id = n.show_id
    WHERE n.rating IS NOT NULL
    AND n.rating NOT IN ('74 min', '84 min', '66 min')
),
genre_counts AS (
    SELECT
        genre,
        COUNT(*) AS total,
        COUNT(*) FILTER (WHERE audience_category = 'Mature') AS mature_count,
        COUNT(*) FILTER (WHERE audience_category = 'Teen')   AS teen_count,
        COUNT(*) FILTER (WHERE audience_category = 'Family') AS family_count
    FROM genre_rating
    WHERE audience_category IS NOT NULL
    GROUP BY genre
    HAVING COUNT(*) >= 50
)
SELECT
    genre,
    total,
    ROUND(mature_count::NUMERIC / total * 100, 2) AS mature_pct,
    ROUND(teen_count::NUMERIC  / total * 100, 2)  AS teen_pct,
    ROUND(family_count::NUMERIC / total * 100, 2) AS family_pct
FROM genre_counts
ORDER BY mature_pct DESC;


-- ============================================================
-- SECTION 4: CONTENT FORMAT
-- ============================================================

-- Q9: How has average movie duration trended over the years?
-- Tracks whether Netflix is shifting toward longer, higher-value films
SELECT
    EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY')) AS year_added,
    ROUND(AVG(SPLIT_PART(duration, ' ', 1)::INT), 2)         AS avg_duration_mins,
    MIN(SPLIT_PART(duration, ' ', 1)::INT)                    AS shortest_movie,
    MAX(SPLIT_PART(duration, ' ', 1)::INT)                    AS longest_movie,
    COUNT(*)                                                   AS total_movies
FROM netflix
WHERE type = 'Movie'
AND date_added IS NOT NULL
AND duration IS NOT NULL
AND EXTRACT(YEAR FROM TO_DATE(date_added, 'Month DD, YYYY')) >= 2015
GROUP BY year_added
ORDER BY year_added;


-- Q10: What is the distribution of season counts across TV Shows?
-- Shows whether Netflix favors limited series or long-running franchises
WITH season_data AS (
    SELECT
        SPLIT_PART(duration, ' ', 1)::INT AS season_count
    FROM netflix
    WHERE type = 'TV Show'
    AND duration IS NOT NULL
),
season_grouped AS (
    SELECT
        CASE
            WHEN season_count = 1              THEN '1 Season (Limited)'
            WHEN season_count = 2              THEN '2 Seasons'
            WHEN season_count = 3              THEN '3 Seasons'
            WHEN season_count BETWEEN 4 AND 6  THEN '4-6 Seasons (Mid-Run)'
            WHEN season_count >= 7             THEN '7+ Seasons (Long-Running)'
        END AS season_category,
        season_count
    FROM season_data
)
SELECT
    season_category,
    COUNT(*)                                                          AS total_shows,
    ROUND(COUNT(*)::NUMERIC / SUM(COUNT(*)) OVER () * 100, 2)        AS pct_of_catalog,
    MIN(season_count)                                                  AS min_seasons,
    MAX(season_count)                                                  AS max_seasons
FROM season_grouped
WHERE season_category IS NOT NULL
GROUP BY season_category
ORDER BY MIN(season_count);


-- ============================================================
-- SECTION 5: TALENT & PARTNERSHIPS
-- ============================================================

-- Q11: Top 10 most frequently credited directors on the platform
-- Identifies recurring creative partnerships rather than isolating one random director
SELECT
    TRIM(unnest(string_to_array(director, ','))) AS director_name,
    COUNT(*)                                      AS total_titles,
    ROUND(COUNT(*) FILTER (WHERE type = 'Movie')::NUMERIC   / COUNT(*) * 100, 2) AS movie_pct,
    ROUND(COUNT(*) FILTER (WHERE type = 'TV Show')::NUMERIC / COUNT(*) * 100, 2) AS tvshow_pct
FROM netflix
WHERE director IS NOT NULL
GROUP BY director_name
ORDER BY total_titles DESC
LIMIT 10;


-- Q12: Actors appearing most frequently across different countries' content
-- Surfaces cross-market talent strategy and international distribution patterns
WITH actor_split AS (
    SELECT
        show_id,
        TRIM(unnest(string_to_array(casts, ','))) AS actor_name
    FROM netflix
    WHERE casts IS NOT NULL
),
country_split AS (
    SELECT
        show_id,
        TRIM(unnest(string_to_array(country, ','))) AS country_name
    FROM netflix
    WHERE country IS NOT NULL
),
actor_country AS (
    SELECT
        a.actor_name,
        c.country_name
    FROM actor_split a
    INNER JOIN country_split c ON a.show_id = c.show_id
),
actor_stats AS (
    SELECT
        actor_name,
        COUNT(*)                     AS total_appearances,
        COUNT(DISTINCT country_name) AS countries_appeared_in
    FROM actor_country
    GROUP BY actor_name
    HAVING COUNT(*) >= 5
)
SELECT
    actor_name,
    total_appearances,
    countries_appeared_in
FROM actor_stats
WHERE countries_appeared_in >= 2
ORDER BY countries_appeared_in DESC, total_appearances DESC
LIMIT 15;


-- ============================================================
-- SECTION 6: DATA QUALITY
-- ============================================================

-- Q13: Missing data percentage broken down by content type
-- Reports data completeness limitations before drawing conclusions
SELECT
    type,
    COUNT(*)                                                                        AS total_titles,
    COUNT(*) FILTER (WHERE director IS NULL)                                        AS missing_director,
    ROUND(COUNT(*) FILTER (WHERE director IS NULL)::NUMERIC / COUNT(*) * 100, 2)   AS missing_director_pct,
    COUNT(*) FILTER (WHERE casts IS NULL)                                           AS missing_casts,
    ROUND(COUNT(*) FILTER (WHERE casts IS NULL)::NUMERIC / COUNT(*) * 100, 2)      AS missing_casts_pct,
    COUNT(*) FILTER (WHERE country IS NULL)                                         AS missing_country,
    ROUND(COUNT(*) FILTER (WHERE country IS NULL)::NUMERIC / COUNT(*) * 100, 2)    AS missing_country_pct,
    COUNT(*) FILTER (WHERE date_added IS NULL)                                      AS missing_date,
    ROUND(COUNT(*) FILTER (WHERE date_added IS NULL)::NUMERIC / COUNT(*) * 100, 2) AS missing_date_pct
FROM netflix
GROUP BY type
ORDER BY type;
