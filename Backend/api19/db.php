<?php

$host = "localhost";
$user = "root";       // change if different
$pass = "";           // change if different
$db   = "ms"; // change this

$conn = new mysqli($host, $user, $pass, $db);

if ($conn->connect_error) {
    die(json_encode([
        "status" => false,
        "message" => "Database connection failed: " . $conn->connect_error
    ]));
}

$conn->set_charset("utf8mb4");
