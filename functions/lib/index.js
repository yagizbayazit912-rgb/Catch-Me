"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.startUpgrade = exports.recordPresence = exports.ensureProfile = void 0;
const app_1 = require("firebase-admin/app");
const firestore_1 = require("firebase-admin/firestore");
const https_1 = require("firebase-functions/v2/https");
const options_1 = require("firebase-functions/v2/options");
const timing_1 = require("./timing");
(0, app_1.initializeApp)();
(0, options_1.setGlobalOptions)({ region: 'europe-west1', maxInstances: 20 });
const db = (0, firestore_1.getFirestore)();
const HEX_SIZE_DEG = 0.0015;
const MAX_ACCURACY_M = 90;
const MAX_HEX_DISTANCE_M = 205;
const HEARTBEAT_MAX_GAP_SEC = 35;
const DAILY_TIME_EARN_CAP_SEC = 2 * 60 * 60;
const RENT_COOLDOWN_SEC = 15 * 60;
const CAPTURE_SEC = 30;
const UPGRADE_COST_SEC = [0, 5 * 60, 30 * 60, 2 * 60 * 60, 8 * 60 * 60, 24 * 60 * 60];
const UPGRADE_BUILD_SEC = [0, 5 * 60, 30 * 60, 2 * 60 * 60, 8 * 60 * 60, 24 * 60 * 60];
const RENT_SEC = [0, 60, 5 * 60, 20 * 60, 60 * 60, 3 * 60 * 60];
const SIEGE_SEC = [10 * 60, 10 * 60, 30 * 60, 2 * 60 * 60, 6 * 60 * 60, 24 * 60 * 60];
const NAMES = ['Arsa', 'Çadır', 'Ev', 'Apartman', 'Otel', 'Gökdelen'];
function uidOf(request) {
    const uid = request.auth?.uid;
    if (!uid)
        throw new https_1.HttpsError('unauthenticated', 'Oturum açılmadı.');
    return uid;
}
function finiteNumber(value, name) {
    if (typeof value !== 'number' || !Number.isFinite(value)) {
        throw new https_1.HttpsError('invalid-argument', `${name} geçerli değil.`);
    }
    return value;
}
function zoneCenter(zoneId) {
    const parts = zoneId.split(':');
    if (parts.length !== 2)
        throw new https_1.HttpsError('invalid-argument', 'Bölge kimliği geçersiz.');
    const q = Number(parts[0]);
    const r = Number(parts[1]);
    if (!Number.isInteger(q) || !Number.isInteger(r)) {
        throw new https_1.HttpsError('invalid-argument', 'Bölge kimliği geçersiz.');
    }
    return {
        lat: r * 1.5 * HEX_SIZE_DEG,
        lng: (q + r / 2) * Math.sqrt(3) * HEX_SIZE_DEG,
    };
}
function distanceMeters(aLat, aLng, bLat, bLng) {
    const rad = Math.PI / 180;
    const dLat = (bLat - aLat) * rad;
    const dLng = (bLng - aLng) * rad;
    const aa = Math.sin(dLat / 2) ** 2 +
        Math.cos(aLat * rad) * Math.cos(bLat * rad) * Math.sin(dLng / 2) ** 2;
    return 6371000 * 2 * Math.atan2(Math.sqrt(aa), Math.sqrt(1 - aa));
}
function clampDelta(now, last) {
    return (0, timing_1.acceptedDelta)(now, last, HEARTBEAT_MAX_GAP_SEC);
}
function dateKey(date) {
    return `${date.getUTCFullYear()}-${date.getUTCMonth()}-${date.getUTCDate()}`;
}
function profileData(data) {
    const oldPoints = Number(data?.points ?? 0);
    const migratedTime = data?.timeBalanceSec ??
        (data?.points !== undefined ? oldPoints * 60 : 2 * 60 * 60);
    return {
        displayName: String(data?.displayName ?? 'Gezgin'),
        colorHex: String(data?.colorHex ?? '#3C7650'),
        timeBalanceSec: Number(migratedTime),
        zonesOwned: Number(data?.zonesOwned ?? 0),
        earnedTodaySec: Number(data?.earnedTodaySec ?? 0),
        earnedDay: String(data?.earnedDay ?? ''),
    };
}
function parseUpgradeReady(data) {
    const value = data.upgradeReadyAt;
    return value?.toMillis();
}
exports.ensureProfile = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const ref = db.collection('users').doc(uid);
    const snap = await ref.get();
    if (!snap.exists) {
        const supplied = (request.data ?? {});
        const displayName = typeof supplied.displayName === 'string' && supplied.displayName.length < 40
            ? supplied.displayName : `Gezgin ${uid.slice(0, 4).toUpperCase()}`;
        await ref.set({
            displayName,
            colorHex: '#3C7650',
            timeBalanceSec: 2 * 60 * 60,
            zonesOwned: 0,
            earnedTodaySec: 0,
            earnedDay: dateKey(new Date()),
            createdAt: firestore_1.FieldValue.serverTimestamp(),
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    else if (snap.data()?.timeBalanceSec === undefined) {
        const legacyPoints = snap.data()?.points;
        await ref.update({
            timeBalanceSec: legacyPoints === undefined ? 2 * 60 * 60 : Number(legacyPoints) * 60,
            updatedAt: firestore_1.FieldValue.serverTimestamp(),
        });
    }
    const fresh = await ref.get();
    return { profile: profileData(fresh.data()) };
});
/**
 * A heartbeat is accepted only when the device reports a reasonably accurate
 * position inside the server-derived hex. Server time is used for every delta;
 * device timestamps are ignored. The same transaction handles capture, time
 * credits, rent and inactive-owner siege progress.
 */
exports.recordPresence = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const data = (request.data ?? {});
    const zoneId = String(data.zoneId ?? '');
    const lat = finiteNumber(data.latitude, 'latitude');
    const lng = finiteNumber(data.longitude, 'longitude');
    const accuracy = finiteNumber(data.accuracy, 'accuracy');
    if (accuracy <= 0 || accuracy > MAX_ACCURACY_M) {
        throw new https_1.HttpsError('failed-precondition', 'Konum doğruluğu yeterli değil.');
    }
    const center = zoneCenter(zoneId);
    if (distanceMeters(lat, lng, center.lat, center.lng) > MAX_HEX_DISTANCE_M + accuracy) {
        throw new https_1.HttpsError('failed-precondition', 'Konum bu altıgenin içinde değil.');
    }
    const zoneRef = db.collection('zones').doc(zoneId);
    const userRef = db.collection('users').doc(uid);
    const presenceRef = userRef.collection('zonePresence').doc(zoneId);
    // Transactions must perform every read before their first write. Read the
    // rent cooldown document up front so the later payout remains atomic.
    const visitRef = userRef.collection('rentVisits').doc(zoneId);
    const result = await db.runTransaction(async (tx) => {
        const [zoneSnap, userSnap, presenceSnap, visitSnap] = await Promise.all([
            tx.get(zoneRef), tx.get(userRef), tx.get(presenceRef), tx.get(visitRef),
        ]);
        const now = Date.now();
        const nowTimestamp = firestore_1.Timestamp.fromMillis(now);
        const user = profileData(userSnap.data());
        const rawZone = zoneSnap.data() ?? {
            ownerId: null, upgradeLevel: 0, baseRentSec: 0,
            centerLat: center.lat, centerLng: center.lng,
            lastOwnerPresenceAt: null,
            siegeLastAt: null,
        };
        const level = (0, timing_1.effectiveLevel)(Number(rawZone.upgradeLevel ?? 0), rawZone.constructionFromLevel, parseUpgradeReady(rawZone), now);
        const previousPresence = presenceSnap.data();
        const previousAt = previousPresence?.lastAt?.toMillis();
        const delta = clampDelta(now, previousAt);
        const previouslyCaptured = String(previousPresence?.capturedZoneId ?? '') === zoneId;
        // A gap longer than the heartbeat window means the player left the cell;
        // do not resume a capture or siege from an old local timer.
        const continuous = userSnap.data()?.activeZoneId === zoneId && previousAt !== undefined &&
            now - previousAt <= HEARTBEAT_MAX_GAP_SEC * 1000;
        const verified = previouslyCaptured && continuous
            ? Number(previousPresence?.verifiedSeconds ?? 0) + delta
            : 0;
        const presencePatch = {
            zoneId, capturedZoneId: zoneId, verifiedSeconds: verified,
            lastAt: nowTimestamp, lastLatitude: lat, lastLongitude: lng,
            lastAccuracy: accuracy, updatedAt: nowTimestamp,
        };
        tx.set(presenceRef, presencePatch, { merge: true });
        const today = dateKey(new Date(now));
        const earnedBefore = user.earnedDay === today ? user.earnedTodaySec : 0;
        const earned = Math.max(0, Math.min(delta, DAILY_TIME_EARN_CAP_SEC - earnedBefore));
        const updatedWallet = user.timeBalanceSec + earned;
        let zone = { ...rawZone };
        let captured = false;
        let rentPaidSec = 0;
        let siegeCompleted = false;
        let siegeProgressSec = 0;
        let ownerId = typeof zone.ownerId === 'string' ? zone.ownerId : null;
        if (ownerId === null && verified >= CAPTURE_SEC) {
            captured = true;
            ownerId = uid;
            zone = {
                ...zone, ownerId: uid, ownerName: user.displayName, colorHex: user.colorHex,
                upgradeLevel: 0, capturedAt: nowTimestamp, lastOwnerPresenceAt: nowTimestamp,
                baseRentSec: 60, centerLat: center.lat, centerLng: center.lng,
                siegeAttackerId: null, siegeProgressSec: 0, siegeRequiredSec: 0,
                siegeLastAt: null,
            };
            tx.set(userRef, { zonesOwned: firestore_1.FieldValue.increment(1) }, { merge: true });
            tx.set(presenceRef, { verifiedSeconds: 0 }, { merge: true });
        }
        else if (ownerId === uid) {
            zone.lastOwnerPresenceAt = nowTimestamp;
            // A completed construction becomes available for the next upgrade here.
            const readyAt = parseUpgradeReady(zone);
            if (readyAt !== undefined && readyAt <= now)
                zone.upgradeReadyAt = null;
        }
        else if (ownerId !== null) {
            const ownerLast = zone.lastOwnerPresenceAt?.toMillis() ?? 0;
            const inactive = ownerLast === 0 || now - ownerLast > 72 * 60 * 60 * 1000;
            const rent = RENT_SEC[level];
            const lastRent = visitSnap.data()?.paidAt?.toMillis() ?? 0;
            if (rent > 0 && now - lastRent >= RENT_COOLDOWN_SEC * 1000 && user.timeBalanceSec >= rent) {
                rentPaidSec = rent;
                tx.set(userRef, { timeBalanceSec: firestore_1.FieldValue.increment(-rent) }, { merge: true });
                tx.set(db.collection('users').doc(ownerId), { timeBalanceSec: firestore_1.FieldValue.increment(rent) }, { merge: true });
                tx.set(visitRef, { paidAt: nowTimestamp, amountSec: rent, zoneId }, { merge: true });
                tx.create(db.collection('ledger').doc(), {
                    type: 'rent', zoneId, fromUserId: uid, toUserId: ownerId,
                    amountSec: rent, createdAt: nowTimestamp,
                });
            }
            // A neglected property can be reclaimed by holding it continuously.
            if (inactive && delta > 0) {
                const attacker = String(zone.siegeAttackerId ?? '');
                const required = SIEGE_SEC[level];
                const siegeLastAt = zone.siegeLastAt?.toMillis();
                const siegeContinuous = attacker === uid && siegeLastAt !== undefined &&
                    now - siegeLastAt <= HEARTBEAT_MAX_GAP_SEC * 1000;
                siegeProgressSec = siegeContinuous
                    ? Number(zone.siegeProgressSec ?? 0) + delta
                    : delta;
                zone.siegeAttackerId = uid;
                zone.siegeProgressSec = siegeProgressSec;
                zone.siegeRequiredSec = required;
                zone.siegeLastAt = nowTimestamp;
                if (siegeProgressSec >= required) {
                    siegeCompleted = true;
                    const oldOwner = ownerId;
                    ownerId = uid;
                    zone = {
                        ...zone, ownerId: uid, ownerName: user.displayName, colorHex: user.colorHex,
                        upgradeLevel: 0, capturedAt: nowTimestamp, lastOwnerPresenceAt: nowTimestamp,
                        siegeAttackerId: null, siegeProgressSec: 0, siegeRequiredSec: 0,
                        siegeLastAt: null,
                    };
                    tx.set(userRef, { zonesOwned: firestore_1.FieldValue.increment(1) }, { merge: true });
                    tx.set(db.collection('users').doc(oldOwner), { zonesOwned: firestore_1.FieldValue.increment(-1) }, { merge: true });
                    tx.create(db.collection('ledger').doc(), {
                        type: 'siege', zoneId, fromUserId: oldOwner, toUserId: uid,
                        amountSec: 0, createdAt: nowTimestamp,
                    });
                }
            }
            else if (!inactive && zone.siegeAttackerId) {
                zone.siegeAttackerId = null;
                zone.siegeProgressSec = 0;
                zone.siegeRequiredSec = 0;
                zone.siegeLastAt = null;
            }
        }
        tx.set(zoneRef, { ...zone, updatedAt: nowTimestamp }, { merge: true });
        tx.set(userRef, {
            timeBalanceSec: updatedWallet - rentPaidSec,
            earnedTodaySec: earnedBefore + earned,
            earnedDay: today,
            lastPresenceAt: nowTimestamp,
            activeZoneId: zoneId,
            updatedAt: nowTimestamp,
        }, { merge: true });
        return {
            captured, siegeCompleted, rentPaidSec, earnedSec: earned,
            timeBalanceSec: updatedWallet - rentPaidSec, ownerId,
            upgradeLevel: Number(zone.upgradeLevel ?? 0),
            siegeProgressSec, siegeRequiredSec: Number(zone.siegeRequiredSec ?? 0),
            captureProgressSec: captured ? CAPTURE_SEC : verified,
            captureRequiredSec: CAPTURE_SEC,
            serverNowMs: now,
        };
    });
    return result;
});
exports.startUpgrade = (0, https_1.onCall)(async (request) => {
    const uid = uidOf(request);
    const data = (request.data ?? {});
    const zoneId = String(data.zoneId ?? '');
    const toLevel = Math.floor(finiteNumber(data.toLevel, 'toLevel'));
    if (toLevel < 1 || toLevel > 5)
        throw new https_1.HttpsError('invalid-argument', 'Seviye geçersiz.');
    const zoneRef = db.collection('zones').doc(zoneId);
    const userRef = db.collection('users').doc(uid);
    const now = Date.now();
    return db.runTransaction(async (tx) => {
        const [zoneSnap, userSnap] = await Promise.all([tx.get(zoneRef), tx.get(userRef)]);
        const zone = zoneSnap.data();
        if (!zone || zone.ownerId !== uid)
            throw new https_1.HttpsError('permission-denied', 'Bu arsa sana ait değil.');
        const current = Number(zone.upgradeLevel ?? 0);
        if (toLevel !== current + 1)
            throw new https_1.HttpsError('failed-precondition', 'Sıradaki seviyeyi açmalısın.');
        const readyAt = parseUpgradeReady(zone);
        if (readyAt !== undefined && readyAt > now) {
            throw new https_1.HttpsError('failed-precondition', 'Mevcut inşaat henüz tamamlanmadı.');
        }
        const user = profileData(userSnap.data());
        const cost = UPGRADE_COST_SEC[toLevel];
        if (user.timeBalanceSec < cost) {
            throw new https_1.HttpsError('failed-precondition', `Bu inşaat için ${Math.ceil(cost / 60)} dakika zaman gerekli.`);
        }
        const completeAt = firestore_1.Timestamp.fromMillis(now + UPGRADE_BUILD_SEC[toLevel] * 1000);
        tx.set(zoneRef, {
            upgradeLevel: toLevel, upgradeReadyAt: completeAt,
            constructionStartedAt: firestore_1.Timestamp.fromMillis(now),
            constructionFromLevel: current, constructionToLevel: toLevel,
            updatedAt: firestore_1.Timestamp.fromMillis(now),
        }, { merge: true });
        tx.set(userRef, { timeBalanceSec: firestore_1.FieldValue.increment(-cost), updatedAt: firestore_1.Timestamp.fromMillis(now) }, { merge: true });
        tx.create(db.collection('ledger').doc(), {
            type: 'upgrade', zoneId, fromUserId: uid, toUserId: uid,
            amountSec: cost, level: toLevel, createdAt: firestore_1.Timestamp.fromMillis(now),
        });
        return { zoneId, upgradeLevel: toLevel, costSec: cost, completeAt: completeAt.toMillis(), name: NAMES[toLevel] };
    });
});
//# sourceMappingURL=index.js.map