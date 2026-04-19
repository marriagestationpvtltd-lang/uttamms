<?php
namespace App\Controllers;

use App\Utils\Response;
use App\Utils\JWT;

class AuthController {
    private $conn;
    
    public function __construct() {
        // Create database connection
        try {
            $this->conn = new \PDO(
                "mysql:host=localhost;dbname=ms;charset=utf8mb4",
                "ms",
                "ms"
            );
            $this->conn->setAttribute(\PDO::ATTR_ERRMODE, \PDO::ERRMODE_EXCEPTION);
            $this->conn->setAttribute(\PDO::ATTR_DEFAULT_FETCH_MODE, \PDO::FETCH_ASSOC);
        } catch (\PDOException $e) {
            Response::serverError('Database connection failed: ' . $e->getMessage());
        }
    }
    
    public function login() {
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (!$input || !isset($input['email']) || !isset($input['password'])) {
            Response::error('Email and password are required', 400);
        }
        
        $email = $input['email'];
        $password = $input['password'];
        
        try {
            // First, let's create users table if it doesn't exist
            $this->createUsersTableIfNotExists();
            
            // Check if admin user exists, if not create one
            $adminCheck = $this->conn->query("SELECT COUNT(*) as count FROM agent_users WHERE email = 'admin@example.com'");
            $adminExists = $adminCheck->fetch()['count'] > 0;
            
            if (!$adminExists) {
                // Create default admin user
                $hashedPassword = password_hash('admin123', PASSWORD_DEFAULT);
                $stmt = $this->conn->prepare("
                    INSERT INTO agent_users (username, email, password_hash, role) 
                    VALUES ('admin', 'admin@example.com', ?, 'admin')
                ");
                $stmt->execute([$hashedPassword]);
            }
            
            // Now check credentials
            $stmt = $this->conn->prepare("SELECT * FROM agent_users WHERE email = ? LIMIT 1");
            $stmt->execute([$email]);
            $user = $stmt->fetch();
            
            if (!$user) {
                Response::error('Invalid credentials', 401);
            }
            
            // Verify password
            if (!password_verify($password, $user['password_hash'])) {
                Response::error('Invalid credentials', 401);
            }
            
            // Generate JWT token
            $token = JWT::encode([
                'user_id' => $user['id'],
                'email' => $user['email'],
                'username' => $user['username'],
                'role' => $user['role'],
                'exp' => time() + (7 * 24 * 60 * 60) // 7 days
            ]);
            
            Response::success([
                'token' => $token,
                'user' => [
                    'id' => $user['id'],
                    'username' => $user['username'],
                    'email' => $user['email'],
                    'avatar_url' => $user['avatar_url'] ?? '',
                    'role' => $user['role']
                ]
            ]);
            
        } catch (\Exception $e) {
            error_log("Login error: " . $e->getMessage());
            Response::serverError('Login failed: ' . $e->getMessage());
        }
    }
    
    public function getCurrentUser() {
        if (!isset($_SESSION['user_id'])) {
            Response::unauthorized();
        }
        
        try {
            $stmt = $this->conn->prepare("SELECT id, username, email, avatar_url, role FROM agent_users WHERE id = ?");
            $stmt->execute([$_SESSION['user_id']]);
            $user = $stmt->fetch();
            
            if (!$user) {
                Response::notFound('User');
            }
            
            Response::success(['user' => $user]);
            
        } catch (\Exception $e) {
            error_log("Get user error: " . $e->getMessage());
            Response::serverError('Failed to fetch user');
        }
    }
    
    public function register() {
        $input = json_decode(file_get_contents('php://input'), true);
        
        if (!$input || !isset($input['email']) || !isset($input['password']) || !isset($input['username'])) {
            Response::error('Email, password and username are required', 400);
        }
        
        $email = $input['email'];
        $password = $input['password'];
        $username = $input['username'];
        
        try {
            // Check if user already exists
            $stmt = $this->conn->prepare("SELECT id FROM agent_users WHERE email = ? OR username = ?");
            $stmt->execute([$email, $username]);
            
            if ($stmt->fetch()) {
                Response::error('User already exists', 409);
            }
            
            // Hash password
            $password_hash = password_hash($password, PASSWORD_DEFAULT);
            
            // Insert new user
            $stmt = $this->conn->prepare("
                INSERT INTO agent_users (username, email, password_hash, role) 
                VALUES (?, ?, ?, 'agent')
            ");
            
            $stmt->execute([$username, $email, $password_hash]);
            $userId = $this->conn->lastInsertId();
            
            // Generate token
            $token = JWT::encode([
                'user_id' => $userId,
                'email' => $email,
                'username' => $username,
                'role' => 'agent',
                'exp' => time() + (7 * 24 * 60 * 60)
            ]);
            
            Response::created([
                'token' => $token,
                'user' => [
                    'id' => $userId,
                    'username' => $username,
                    'email' => $email,
                    'role' => 'agent'
                ]
            ]);
            
        } catch (\Exception $e) {
            error_log("Registration error: " . $e->getMessage());
            Response::serverError('Registration failed: ' . $e->getMessage());
        }
    }
    
    private function createUsersTableIfNotExists() {
        // agent_users table is now defined in the main ms database schema (schema.sql, section 30).
        // This method is kept for backwards compatibility but performs no action.
    }
}
?>