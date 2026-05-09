import { initializeApp } from "firebase-admin/app";
import { getFirestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import { logger } from "firebase-functions";
import { onDocumentCreated } from "firebase-functions/v2/firestore";

initializeApp();

type NotificationEvent = {
  body?: string;
  familyGroupID?: string;
  kind?: string;
  teenID?: string;
  title?: string;
};

export const sendTeenDriveAlert = onDocumentCreated("notificationEvents/{eventId}", async (event) => {
  const data = event.data?.data() as NotificationEvent | undefined;
  if (!data?.familyGroupID) {
    logger.info("Notification event skipped: missing familyGroupID", { eventId: event.params.eventId });
    return;
  }

  const db = getFirestore();
  const familySnap = await db.collection("familyGroups").doc(data.familyGroupID).get();
  const parentIDs = (familySnap.get("parentIDs") ?? []) as string[];

  if (!parentIDs.length) {
    logger.info("Notification event skipped: no parent IDs", { familyGroupID: data.familyGroupID });
    return;
  }

  const parentSnaps = await Promise.all(
    parentIDs.map((id) => db.collection("parentProfiles").doc(id).get()),
  );

  const tokens = parentSnaps
    .map((snap) => snap.get("fcmToken"))
    .filter((token): token is string => typeof token === "string" && token.length > 0);

  if (!tokens.length) {
    logger.info("Notification event skipped: no parent FCM tokens", { familyGroupID: data.familyGroupID });
    return;
  }

  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: {
      title: data.title ?? "Teen Drive Alert",
      body: data.body ?? "New driving alert",
    },
    data: {
      familyGroupID: data.familyGroupID,
      kind: data.kind ?? "",
      teenID: data.teenID ?? "",
    },
    apns: {
      payload: {
        aps: {
          sound: "default",
        },
      },
    },
  });

  logger.info("Teen Drive alert sent", {
    eventId: event.params.eventId,
    failureCount: response.failureCount,
    successCount: response.successCount,
  });
});
