<?php
header('Content-Type: application/json; charset=utf-8');

try {
    // DB connection
    $dbHost = "127.0.0.1";
    $dbName = "ms";
    $dbUser = "ms";
    $dbPass = "ms";

    $pdo = new PDO(
        "mysql:host=$dbHost;dbname=$dbName;charset=utf8",
        $dbUser,
        $dbPass,
        [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC
        ]
    );

    // Fetch packages
    $stmt = $pdo->prepare("
        SELECT 
            id,
            name,
            duration,
            description,
            price
        FROM packageList
        ORDER BY price ASC
    ");
    $stmt->execute();

    $packages = $stmt->fetchAll();

    echo json_encode([
        'success' => true,
        'data' => $packages
    ]);

} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'success' => false,
        'message' => $e->getMessage()
    ]);
}
