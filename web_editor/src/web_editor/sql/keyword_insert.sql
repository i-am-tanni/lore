INSERT INTO public.keyword (keyword)
VALUES (lower($1))
ON CONFLICT ((lower(keyword))) 
DO UPDATE SET keyword = EXCLUDED.keyword
RETURNING keyword_id;
