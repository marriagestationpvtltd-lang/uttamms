<?php
/**
 * Lightweight content-safety helper for reels/stories.
 *
 * This is a first-line filter:
 * - blocks explicit sexual text in captions/comments
 * - records moderation jobs for audit/manual review workflows
 */

function moderation_contains_prohibited_text(string $text, array &$matchedWords = []): bool
{
    $normalized = mb_strtolower(trim($text));
    if ($normalized === '') {
        return false;
    }

    $blockedWords = [
        'sex',
        'sexy',
        'porn',
        'xxx',
        'adult',
        'nude',
        'nudity',
        'escort',
        'hookup',
        '18+',
        'sexual',
        'intimate',
    ];

    $found = [];
    foreach ($blockedWords as $word) {
        if (str_contains($normalized, $word)) {
            $found[] = $word;
        }
    }

    $matchedWords = array_values(array_unique($found));
    return !empty($matchedWords);
}

function moderation_record_job(
    PDO $pdo,
    string $entityType,
    int $entityId,
    int $userId,
    string $scanStatus,
    string $scanResult,
    float $confidence,
    string $provider,
    array $rawResponse = []
): void {
    $stmt = $pdo->prepare(
        'INSERT INTO media_moderation_jobs
            (entity_type, entity_id, user_id, scan_status, scan_result, confidence, provider, raw_response_json, created_at, updated_at)
         VALUES
            (:entity_type, :entity_id, :user_id, :scan_status, :scan_result, :confidence, :provider, :raw_response_json, NOW(), NOW())'
    );

    $stmt->execute([
        ':entity_type' => $entityType,
        ':entity_id' => $entityId,
        ':user_id' => $userId,
        ':scan_status' => $scanStatus,
        ':scan_result' => $scanResult,
        ':confidence' => $confidence,
        ':provider' => $provider,
        ':raw_response_json' => json_encode($rawResponse, JSON_UNESCAPED_UNICODE),
    ]);
}
