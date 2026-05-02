<?php
header('Content-Type: application/json; charset=utf-8');

try {
    // === DATABASE CONFIG ===
    $dbHost = "127.0.0.1";
    $dbName = "ms";     // replace with your DB name
    $dbUser = "root";     // replace with your DB username
    $dbPass = "root";     // replace with your DB password

    $pdo = new PDO(
        "mysql:host=$dbHost;dbname=$dbName;charset=utf8mb4",
        $dbUser,
        $dbPass,
        [PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION]
    );

    // FETCH ALL SERVICES
    $sql = "SELECT * FROM services ORDER BY id DESC";
    $stmt = $pdo->prepare($sql);
    $stmt->execute();
    $services = $stmt->fetchAll(PDO::FETCH_ASSOC);

    echo json_encode([
        "success" => true,
        "message" => "Services fetched successfully",
        "data" => $services
    ], JSON_PRETTY_PRINT);

} catch (Exception $e) {
    echo json_encode([
        "success" => false,
        "message" => "Server error: " . $e->getMessage()
    ]);
}
?>
