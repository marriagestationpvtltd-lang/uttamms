<?php
// Enable error reporting (for development)
ini_set('display_errors', 1);
error_reporting(E_ALL);

// Set JSON header
header('Content-Type: application/json; charset=utf-8');

// Database configuration
$host = 'localhost';
$dbName = 'ms';
$dbUser = 'root';
$dbPass = '';

try {
    // Create PDO connection
    $pdo = new PDO("mysql:host=$host;dbname=$dbName;charset=utf8mb4", $dbUser, $dbPass);
    $pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);

    // Prepare SQL query
    $stmt = $pdo->prepare("SELECT id, name FROM countries ORDER BY name ASC");
    $stmt->execute();

    // Fetch all countries
    $countries = $stmt->fetchAll(PDO::FETCH_ASSOC);

    // Return JSON response
    echo json_encode([
        'status' => 1,
        'data' => $countries
    ]);

} catch (PDOException $e) {
    // Handle connection errors
    echo json_encode([
        'status' => 0,
        'error' => $e->getMessage()
    ]);
}
?>
