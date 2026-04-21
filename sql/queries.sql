-- 1. Daily Active Users (DAU)
SELECT
  event_date,
  COUNT(DISTINCT user_id) AS dau
FROM product_events
WHERE event_name IN ('login', 'core_workflow_completed', 'feature_used')
GROUP BY event_date
ORDER BY event_date;

-- 2. Monthly Active Users (MAU)
SELECT
  DATE_TRUNC('month', event_date) AS activity_month,
  COUNT(DISTINCT user_id) AS mau
FROM product_events
WHERE event_name IN ('login', 'core_workflow_completed', 'feature_used')
GROUP BY 1
ORDER BY 1;

-- 3. Rolling DAU/MAU Ratio
WITH daily_users AS (
  SELECT DISTINCT
    user_id,
    event_date
  FROM product_events
  WHERE event_name IN ('login', 'core_workflow_completed', 'feature_used')
),
rolling_activity AS (
  SELECT
    d1.event_date,
    COUNT(DISTINCT d1.user_id) AS dau,
    COUNT(DISTINCT d2.user_id) AS mau
  FROM daily_users d1
  LEFT JOIN daily_users d2
    ON d2.event_date BETWEEN d1.event_date - INTERVAL '29 day' AND d1.event_date
  GROUP BY d1.event_date
)
SELECT
  event_date,
  dau,
  mau,
  ROUND(dau * 1.0 / NULLIF(mau, 0), 4) AS dau_mau_ratio
FROM rolling_activity
ORDER BY event_date;

-- 4. Weekly Cohort Retention
WITH signups AS (
  SELECT
    user_id,
    DATE_TRUNC('week', signup_date) AS cohort_week
  FROM users
),
activity AS (
  SELECT DISTINCT
    user_id,
    DATE_TRUNC('week', event_date) AS activity_week
  FROM product_events
),
cohorts AS (
  SELECT
    s.cohort_week,
    a.activity_week,
    DATE_PART('week', a.activity_week - s.cohort_week) AS week_number,
    COUNT(DISTINCT a.user_id) AS retained_users
  FROM signups s
  JOIN activity a
    ON s.user_id = a.user_id
   AND a.activity_week >= s.cohort_week
  GROUP BY 1, 2, 3
),
cohort_size AS (
  SELECT
    cohort_week,
    COUNT(DISTINCT user_id) AS cohort_users
  FROM signups
  GROUP BY 1
)
SELECT
  c.cohort_week,
  c.week_number,
  cs.cohort_users,
  c.retained_users,
  ROUND(c.retained_users * 1.0 / NULLIF(cs.cohort_users, 0), 4) AS retention_rate
FROM cohorts c
JOIN cohort_size cs
  ON c.cohort_week = cs.cohort_week
ORDER BY c.cohort_week, c.week_number;

-- 5. Activation Rate in First 7 Days
WITH new_users AS (
  SELECT
    user_id,
    signup_date
  FROM users
),
activated_users AS (
  SELECT DISTINCT
    n.user_id
  FROM new_users n
  JOIN product_events e
    ON n.user_id = e.user_id
   AND e.event_name = 'core_workflow_completed'
   AND e.event_date BETWEEN n.signup_date AND n.signup_date + INTERVAL '7 day'
)
SELECT
  COUNT(DISTINCT a.user_id) AS activated_users,
  COUNT(DISTINCT n.user_id) AS total_new_users,
  ROUND(COUNT(DISTINCT a.user_id) * 1.0 / NULLIF(COUNT(DISTINCT n.user_id), 0), 4) AS activation_rate
FROM new_users n
LEFT JOIN activated_users a
  ON n.user_id = a.user_id;

-- 6. Feature Adoption by New Users
WITH first_14_days AS (
  SELECT
    u.user_id,
    e.event_name
  FROM users u
  JOIN product_events e
    ON u.user_id = e.user_id
   AND e.event_date BETWEEN u.signup_date AND u.signup_date + INTERVAL '14 day'
)
SELECT
  event_name,
  COUNT(DISTINCT user_id) AS users_using_feature
FROM first_14_days
GROUP BY event_name
ORDER BY users_using_feature DESC;

-- 6. Feature Adoption by New Users
WITH first_14_days AS (
  SELECT
    u.user_id,
    e.event_name
  FROM users u
  JOIN product_events e
    ON u.user_id = e.user_id
   AND e.event_date BETWEEN u.signup_date AND u.signup_date + INTERVAL '14 day'
)
SELECT
  event_name,
  COUNT(DISTINCT user_id) AS users_using_feature
FROM first_14_days
GROUP BY event_name
ORDER BY users_using_feature DESC;

-- 7. Drop-Off Window Analysis (Weeks 3-5)
WITH user_weeks AS (
  SELECT DISTINCT
    u.user_id,
    DATE_TRUNC('week', u.signup_date) AS cohort_week,
    DATE_PART('week', DATE_TRUNC('week', e.event_date) - DATE_TRUNC('week', u.signup_date)) AS weeks_since_signup
  FROM users u
  JOIN product_events e
    ON u.user_id = e.user_id
)
SELECT
  cohort_week,
  weeks_since_signup,
  COUNT(DISTINCT user_id) AS active_users
FROM user_weeks
WHERE weeks_since_signup BETWEEN 0 AND 8
GROUP BY cohort_week, weeks_since_signup
ORDER BY cohort_week, weeks_since_signup;

-- 8. Funnel Query: Signup -> Onboarding Complete -> Core Workflow
WITH signup_stage AS (
  SELECT user_id, MIN(event_date) AS signup_time
  FROM product_events
  WHERE event_name = 'signup'
  GROUP BY user_id
),
onboarding_stage AS (
  SELECT e.user_id, MIN(e.event_date) AS onboarding_time
  FROM product_events e
  JOIN signup_stage s
    ON e.user_id = s.user_id
   AND e.event_date >= s.signup_time
  WHERE e.event_name = 'onboarding_completed'
  GROUP BY e.user_id
),
workflow_stage AS (
  SELECT e.user_id, MIN(e.event_date) AS workflow_time
  FROM product_events e
  JOIN onboarding_stage o
    ON e.user_id = o.user_id
   AND e.event_date >= o.onboarding_time
  WHERE e.event_name = 'core_workflow_completed'
  GROUP BY e.user_id
)
SELECT
  (SELECT COUNT(*) FROM signup_stage) AS signup_users,
  (SELECT COUNT(*) FROM onboarding_stage) AS onboarding_users,
  (SELECT COUNT(*) FROM workflow_stage) AS workflow_users;

