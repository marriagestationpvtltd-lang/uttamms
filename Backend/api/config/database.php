<?php
class Database {
    private $host = "localhost";
    private $db_name = "ms";
    private $username = "ms";
    private $password = "ms";
    private $conn;

    public function connect() {
        $this->conn = null;
        try {
            $this->conn = new PDO(
                "mysql:host=" . $this->host . ";dbname=" . $this->db_name,
                $this->username,
                $this->password
            );
            $this->conn->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $this->conn->exec("set names utf8");
        } catch(PDOException $e) {
            error_log("Connection Error: " . $e->getMessage());
        }
        return $this->conn;
    }
}
?>