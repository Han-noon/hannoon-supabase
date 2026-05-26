-- user_profile_images: 유저 프로필 사진 (public, 5MB)
-- event_images: 이벤트 이미지 (public, 10MB, service_role만 업로드)

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES
  (
    'user_profile_images',
    'user_profile_images',
    true,
    5242880,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  ),
  (
    'event_images',
    'event_images',
    true,
    10485760,
    ARRAY['image/jpeg', 'image/png', 'image/webp']
  );

-- user_profile_images: 인증된 유저가 자신의 폴더({uid}/...)에만 조회/업로드/삭제 가능
CREATE POLICY "user_profile_images_select"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'user_profile_images'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "user_profile_images_insert"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'user_profile_images'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "user_profile_images_update"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'user_profile_images'
  AND auth.uid()::text = (storage.foldername(name))[1]
);

CREATE POLICY "user_profile_images_delete"
ON storage.objects FOR DELETE
TO authenticated
USING (
  bucket_id = 'user_profile_images'
  AND auth.uid()::text = (storage.foldername(name))[1]
);
