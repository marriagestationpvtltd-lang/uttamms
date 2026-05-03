<?php
header('Content-Type: application/json; charset=utf-8');

/* ══════════════════════════════════════════════════════════════════════════
     match.php  —  Weighted multi-criteria partner match percentage
     ══════════════════════════════════════════════════════════════════════════
     Score weights (total = 100 pts):
         Age            20   Religion       15   Marital status 10
         Height          8   Mother tongue   5   Country         5
         State           2   City            2   Diet            5
         Smoke           3   Drink           3   Family type     3
         Profession      4   Annual income   3   Caste           2
         Complexion      2   Body type       2   Profile photo   5
         Verified        3
     ══════════════════════════════════════════════════════════════════════════ */

try {
    $baseUrl = ((isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') ? 'https' : 'http')
        . '://' . ($_SERVER['HTTP_HOST'] ?? 'localhost') . '/uttamms/Backend/Api2/';

    $pdo = new PDO(
        "mysql:host=127.0.0.1;dbname=ms;charset=utf8mb4",
        "root", "",
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ]
    );

    $userid = isset($_REQUEST['userid']) ? intval($_REQUEST['userid']) : 0;
    if ($userid <= 0) {
        echo json_encode(["success" => false, "message" => "Invalid userid"]);
        exit;
    }

    /* ── LIKES sent by requester ── */
    $stmtLikes = $pdo->prepare("SELECT receiver_id FROM likes WHERE sender_id = :me");
    $stmtLikes->execute([":me" => $userid]);
    $likedUserIds = array_column($stmtLikes->fetchAll(), 'receiver_id');

    /* ── REQUESTER gender ── */
    $stmt = $pdo->prepare("SELECT gender FROM users WHERE id = :id LIMIT 1");
    $stmt->execute([":id" => $userid]);
    $user = $stmt->fetch();
    if (!$user) {
        echo json_encode(["success" => false, "message" => "User not found"]);
        exit;
    }
    $userGender = $user['gender'];

    /* ── REQUESTER partner preferences (all fields) ── */
    $stmt = $pdo->prepare("SELECT * FROM user_partner WHERE userid = :uid LIMIT 1");
    $stmt->execute([":uid" => $userid]);
    $pref = $stmt->fetch();
    if (!$pref) {
        echo json_encode(["success" => true, "matched_users" => []]);
        exit;
    }

    /* ── CANDIDATES with all matchable fields ── */
    $stmt = $pdo->prepare("
        SELECT 
            u.id AS userid,
            upd.memberid,
            u.firstName,
            u.lastName,
            u.gender,
            u.isVerified,
            u.isOnline AS is_online,
            u.profile_picture,
            u.privacy,
            ROUND(DATEDIFF(CURDATE(), upd.birthDate)/365) AS age,
            upd.height_name,
            h.name                                       AS height_cm,
            ms.name                                      AS marital_status,
            r.name                                       AS religion,
            com.name                                     AS caste,
            upd.complexion,
            upd.bodyType                                 AS body_type,
            upd.familyType                               AS family_type,
            upd.motherTongue                             AS mother_tongue,
            upd.anyDisability                            AS any_disability,
            pa.country,
            pa.state,
            pa.city,
            COALESCE(NULLIF(ec.designation, ''), NULLIF(ec.occupationtype, '')) AS profession,
            COALESCE(NULLIF(ec.educationtype, ''), NULLIF(ec.degree, '')) AS education,
            ec.annualincome                              AS annual_income,
            CASE WHEN pkg.net_amount > 0 THEN 1 ELSE 0 END AS is_paid,
            ls.diet,
            ls.smoke,
            ls.drinks
        FROM users u
        INNER JOIN userpersonaldetail upd ON upd.userId = u.id
                         AND upd.id = (SELECT MAX(id) FROM userpersonaldetail WHERE userId = u.id)
        LEFT JOIN  height             h   ON h.id         = upd.heightId
        LEFT JOIN  maritalstatus      ms  ON ms.id        = upd.maritalStatusId
        LEFT JOIN  religion           r   ON r.id         = upd.religionId
        LEFT JOIN  community          com ON com.id       = upd.communityId
        LEFT JOIN  permanent_address  pa  ON pa.userid    = u.id
                        AND pa.id = (SELECT MAX(id) FROM permanent_address WHERE userid = u.id)
        LEFT JOIN  educationcareer    ec  ON ec.userid    = u.id
                        AND ec.id = (SELECT MAX(id) FROM educationcareer WHERE userid = u.id)
        LEFT JOIN  (
            SELECT userId, MAX(netAmount) AS net_amount
            FROM userpackage
            GROUP BY userId
        ) pkg ON pkg.userId = u.id
        LEFT JOIN  user_lifestyle     ls  ON ls.userid    = u.id
        WHERE u.id      != :userid
          AND u.gender  != :gender
          AND u.id NOT IN (SELECT userid FROM delete_request WHERE status = 'pending')
          AND NOT EXISTS (
              SELECT 1 FROM blocks b
              WHERE (b.blocker_id = :userid AND b.blocked_id = u.id)
                 OR (b.blocker_id = u.id    AND b.blocked_id = :userid)
          )
    ");
    $stmt->execute([
        ":userid" => $userid,
        ":gender" => $userGender
    ]);
    $candidates = $stmt->fetchAll();

    /* ══════════════════════════════════════════════════════════════════════
       HELPERS
       ══════════════════════════════════════════════════════════════════════ */

    /**
     * Check whether a candidate value satisfies a (possibly comma-separated)
     * preference string.
     *
     *  - empty / null pref  → auto-pass (no preference = everyone welcome)
     *  - "any" / "doesn't matter" → auto-pass
     *  - comma-separated list  → candidate must be in the list
     *  - otherwise exact match (case-insensitive)
     */
    function prefMatches(?string $prefValue, ?string $candidateValue, ?callable $normalizer = null): bool {
        if (empty($prefValue)) return true;

        $pv = strtolower(trim($prefValue));
        if ($pv === 'any' || $pv === "doesn't matter" || $pv === 'doesnt matter') return true;

        if (empty($candidateValue)) return false;

        $cv = strtolower(trim($candidateValue));
        if ($normalizer) $cv = $normalizer($cv);

        $parts = array_map('trim', explode(',', $pv));
        foreach ($parts as $part) {
            $checkPart = $normalizer ? $normalizer($part) : $part;
            if ($checkPart === $cv) return true;
        }
        return false;
    }

    /* ══════════════════════════════════════════════════════════════════════
       SCORE WEIGHTS  (sum of preference weights = 92, plus 8 quality bonus)
       ══════════════════════════════════════════════════════════════════════ */
        $W_AGE        = 20;
        $W_RELIGION   = 15;
        $W_MARITAL    = 10;
        $W_HEIGHT     =  8;
        $W_MTONGUE    =  5;
        $W_COUNTRY    =  5;
        $W_STATE      =  2;
        $W_CITY       =  2;
        $W_DIET       =  5;
        $W_SMOKE      =  3;
        $W_DRINK      =  3;
        $W_FAMILY     =  3;
        $W_PROFESSION =  4;
        $W_INCOME     =  3;
        $W_CASTE      =  2;
        $W_COMPLEXION =  2;
        $W_BODYTYPE   =  2;
        $W_PHOTO      =  5;
        $W_VERIFIED   =  3;

    /* Marital-status normaliser: maps pref values → DB lookup names */
    $msNorm = function(?string $v): string {
        if (empty($v)) return '';
        $lv = strtolower(trim($v));
        $map = [
            'single'          => 'still unmarried',
            'never married'   => 'still unmarried',
            'waiting divorce' => 'divorced',
        ];
        return $map[$lv] ?? $lv;
    };

    $results = [];
    foreach($candidates as $c){
        $score = 0;

        /* 1. AGE (20) */
        $age    = intval($c['age']);
        $minAge = (!isset($pref['minage']) || $pref['minage'] === '') ? null : intval($pref['minage']);
        $maxAge = (!isset($pref['maxage']) || $pref['maxage'] === '') ? null : intval($pref['maxage']);

        if ($minAge === null && $maxAge === null) {
            $score += $W_AGE;
        } else {
            $inMin = ($minAge === null) || ($age >= $minAge);
            $inMax = ($maxAge === null) || ($age <= $maxAge);
            if ($inMin && $inMax) {
                $score += $W_AGE;
            } else {
                $delta = 0;
                if ($minAge !== null && $age < $minAge) $delta = $minAge - $age;
                if ($maxAge !== null && $age > $maxAge) $delta = max($delta, $age - $maxAge);
                if ($delta <= 3)     $score += (int)($W_AGE * 0.6);  // 12 pts
                elseif ($delta <= 6) $score += (int)($W_AGE * 0.3);  //  6 pts
                // > 6 years outside → 0
            }
        }

        /* 2. RELIGION (15) */
        $score += prefMatches($pref['religion'], $c['religion']) ? $W_RELIGION : 0;

        /* 3. MARITAL STATUS (10) */
        $score += prefMatches($pref['maritalstatus'], $c['marital_status'], $msNorm) ? $W_MARITAL : 0;

        /* 4. HEIGHT (8) */
        $minH  = (!isset($pref['minheight']) || $pref['minheight'] === '') ? null : intval($pref['minheight']);
        $maxH  = (!isset($pref['maxheight']) || $pref['maxheight'] === '') ? null : intval($pref['maxheight']);
        $candH = !empty($c['height_cm']) ? intval($c['height_cm']) : null;

        if ($minH === null && $maxH === null) {
            $score += $W_HEIGHT;
        } elseif ($candH !== null) {
            $inMinH = ($minH === null) || ($candH >= $minH);
            $inMaxH = ($maxH === null) || ($candH <= $maxH);
            if ($inMinH && $inMaxH) {
                $score += $W_HEIGHT;
            } else {
                $hDelta = 0;
                if ($minH !== null && $candH < $minH) $hDelta = $minH - $candH;
                if ($maxH !== null && $candH > $maxH) $hDelta = max($hDelta, $candH - $maxH);
                if ($hDelta <= 5) $score += (int)($W_HEIGHT * 0.5);  // 4 pts
            }
        }

        /* 5. MOTHER TONGUE (5) */
        $score += prefMatches($pref['mothertoungue'], $c['mother_tongue']) ? $W_MTONGUE : 0;

        /* 6. COUNTRY (5) */
        $score += prefMatches($pref['country'], $c['country']) ? $W_COUNTRY : 0;

        /* 7. STATE (2) */
        $score += prefMatches($pref['state'], $c['state']) ? $W_STATE : 0;

        /* 8. CITY (2) */
        $score += prefMatches($pref['city'], $c['city']) ? $W_CITY : 0;

        /* 9. DIET (5) */
        $score += prefMatches($pref['diet'], $c['diet']) ? $W_DIET : 0;

        /* 10. SMOKE ACCEPTANCE (3) */
        $smokeAccept = strtolower(trim($pref['smokeaccept'] ?? ''));
        $candSmoke   = strtolower(trim($c['smoke'] ?? ''));
        if (empty($smokeAccept)
            || $smokeAccept === "doesn't matter"
            || $smokeAccept === 'any'
            || $smokeAccept === 'yes') {
            $score += $W_SMOKE;
        } elseif ($smokeAccept === 'no' || $smokeAccept === "doesn't smoke") {
            if (empty($candSmoke) || $candSmoke === 'no') $score += $W_SMOKE;
        }

        /* 11. DRINK ACCEPTANCE (3) */
        $drinkAccept = strtolower(trim($pref['drinkaccept'] ?? ''));
        $candDrink   = strtolower(trim($c['drinks'] ?? ''));
        if (empty($drinkAccept)
            || $drinkAccept === "doesn't matter"
            || $drinkAccept === 'any'
            || $drinkAccept === 'yes') {
            $score += $W_DRINK;
        } elseif ($drinkAccept === 'no' || $drinkAccept === "doesn't drink") {
            if (empty($candDrink) || $candDrink === 'no') $score += $W_DRINK;
        }

        /* 12. FAMILY TYPE (3) */
        $score += prefMatches($pref['familytype'], $c['family_type']) ? $W_FAMILY : 0;

        /* 13. PROFESSION (4) */
        $score += prefMatches($pref['proffession'], $c['profession']) ? $W_PROFESSION : 0;

        /* 14. ANNUAL INCOME (3) */
        $score += prefMatches($pref['annualincome'], $c['annual_income']) ? $W_INCOME : 0;

        /* 15. CASTE (2) */
        $score += prefMatches($pref['caste'], $c['caste']) ? $W_CASTE : 0;

        /* 16. COMPLEXION (2) */
        $score += prefMatches($pref['complexion'], $c['complexion']) ? $W_COMPLEXION : 0;

        /* 17. BODY TYPE (2) */
        $score += prefMatches($pref['bodytype'], $c['body_type']) ? $W_BODYTYPE : 0;

        /* 18. PROFILE PHOTO QUALITY BONUS (5) */
        if (!empty($c['profile_picture'])) $score += $W_PHOTO;

        /* 19. VERIFIED ACCOUNT BONUS (3) */
        if (intval($c['isVerified']) === 1) $score += $W_VERIFIED;

        /* Skip very low compatibility matches */
        if ($score < 20) continue;

        $matchPercent = min(100, $score);

        /* ── LIKE STATUS ── */
        $isLiked = in_array($c['userid'], $likedUserIds);

        /* ================= PHOTO REQUEST ================= */
        /* ── PHOTO REQUEST ── */
        $photo_request  = "not sent";
        $can_view_photo = false;

        $stmtPhoto = $pdo->prepare("
            SELECT status
            FROM proposals
            WHERE request_type = 'Photo'
            AND (
                (sender_id = :me AND receiver_id = :other)
                OR (sender_id = :other AND receiver_id = :me)
            )
            ORDER BY id DESC
            LIMIT 1
        ");
        $stmtPhoto->execute([
            ":me"    => $userid,
            ":other" => $c['userid']
        ]);

        if ($row = $stmtPhoto->fetch()) {
            $photo_request = ($row['status'] === 'accepted')
                ? 'accepted'
                : 'pending';
            $can_view_photo = ($row['status'] === 'accepted');
        }

        /* ── GALLERY ── */
        $stmtImages = $pdo->prepare("
            SELECT id, imageUrl, createdDate, updatedDate
            FROM userimagegallery
            WHERE userId = :uid AND isActive = 1 AND isDelete = 0
            ORDER BY createdDate DESC
        ");
        $stmtImages->execute([":uid" => $c['userid']]);
        $gallery = $stmtImages->fetchAll();

        $profilePicture = $c['profile_picture'] ?? '';
        if (!empty($profilePicture) && strpos($profilePicture, 'http') !== 0) {
            $profilePicture = $baseUrl . ltrim($profilePicture, '/');
        }

        /* ── RESULT RECORD ── */
        $results[] = [
            "userid"          => $c['userid'],
            "memberid"        => $c['memberid'],
            "firstName"       => $c['firstName'],
            "lastName"        => $c['lastName'],
            "gender"          => $c['gender'] ?? '',
            "isVerified"      => $c['isVerified'],
            "is_online"       => intval($c['is_online'] ?? 0),
            "is_paid"         => intval($c['is_paid'] ?? 0),
            "profile_picture" => $profilePicture,
            "privacy"         => $c['privacy'],
            "age"             => $age,
            "height_name"     => $c['height_name'],
            "marital_status"  => $c['marital_status'] ?? '',
            "education"       => $c['education'] ?? '',
            "occupation"      => $c['profession'] ?? '',
            "country"         => $c['country'] ?? '',
            "city"            => $c['city'] ?? '',
            "designation"     => $c['profession'] ?? '',
            "matchPercent"    => $matchPercent,
            "photo_request"   => $photo_request,
            "can_view_photo"  => $can_view_photo,
            "like"            => $isLiked,
            "gallery"         => $gallery,
        ];
    }

    usort($results, fn($a, $b) => $b['matchPercent'] <=> $a['matchPercent']);

    echo json_encode([
        "success"       => true,
        "matched_users" => $results,
    ]);

} catch (Exception $e) {
    echo json_encode([
        "success"  => false,
        "message"  => $e->getMessage(),
    ]);
}
