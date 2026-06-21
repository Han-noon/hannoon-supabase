import { createClient } from "jsr:@supabase/supabase-js@2";
import * as OneSignal from "npm:@onesignal/node-onesignal@5.7.0";

interface NotificationRecord {
  id: number;
  user_id: string;
  topic_id: number;
  event_id: number;
  read_at: string | null;
  created_at: string;
}

Deno.serve(async (req: Request) => {
  // 이 엔드포인트는 공개 URL이므로, DB 트리거 외의 호출을 차단하기 위해 공유 시크릿으로 검증한다.
  // secret 미설정 시 검증 생략 → 로컬 개발 편의를 위한 의도적 허용.
  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (secret && req.headers.get("Authorization") !== `Bearer ${secret}`) {
    return new Response("Unauthorized", { status: 401 });
  }

  const record: NotificationRecord = await req.json();
  console.log("[notify-onesignal] 알림 수신: notification_id=", record.id, "user_id=", record.user_id);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data, error } = await supabase
    .from("topics")
    .select("title")
    .eq("id", record.topic_id)
    .single();

  if (error || !data) {
    console.error("Failed to fetch topic:", error);
    return new Response("Internal Error", { status: 500 });
  }
  console.log("[notify-onesignal] 토픽 조회 성공:", (data as { title: string }).title);

  const configuration = OneSignal.createConfiguration({
    restApiKey: Deno.env.get("ONESIGNAL_REST_API_KEY")!,
  });
  const client = new OneSignal.DefaultApi(configuration);

  const notification = new OneSignal.Notification();
  notification.app_id = Deno.env.get("ONESIGNAL_APP_ID")!;
  // OneSignal v2 API: include_aliases로 external_id 타겟팅, target_channel 명시 필요
  notification.include_aliases = { external_id: [record.user_id] };
  notification.target_channel = "push";
  const message = `${(data as { title: string }).title}에 새로운 사건이 등록되었습니다.`;
  notification.contents = { en: message, ko: message };
  notification.data = {
    notification_id: record.id,
    event_id: record.event_id,
    topic_id: record.topic_id,
  };
  // 클릭 시 열 URL을 서버에서 지정 (웹 푸시는 OneSignal 기본 서비스워커가 직접 엶)
  notification.url = `https://d2bpw1mru85w1q.cloudfront.net/event-detail/${record.event_id}`;

  try {
    await client.createNotification(notification);
    console.log("[notify-onesignal] 푸시 전송 완료: notification_id=", record.id);
  } catch (e) {
    console.error("OneSignal error:", e);
    return new Response("OneSignal Error", { status: 502 });
  }

  return new Response("OK", { status: 200 });
});
