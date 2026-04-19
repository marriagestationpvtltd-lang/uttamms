<?php
namespace App\Models;

use PDO;

class Chat {
    private $conn;
    private $table = 'ac_chats';
    
    public function __construct($db) {
        $this->conn = $db;
    }
    
    public function getAll($userId, $search = '', $filter = 'all') {
        $query = "SELECT c.* FROM " . $this->table . " c WHERE c.assigned_to = :user_id";
        
        $params = ['user_id' => $userId];
        
        if (!empty($search)) {
            $query .= " AND (c.name LIKE :search OR c.last_message LIKE :search)";
            $params['search'] = "%$search%";
        }
        
        if ($filter === 'unread') {
            $query .= " AND c.is_unread = 1";
        } elseif ($filter === 'pinned') {
            $query .= " AND c.is_pinned = 1";
        }
        
        $query .= " ORDER BY c.is_pinned DESC, c.updated_at DESC";
        
        $stmt = $this->conn->prepare($query);
        $stmt->execute($params);
        
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
    
    public function findById($id) {
        $query = "SELECT * FROM " . $this->table . " WHERE id = :id";
        $stmt = $this->conn->prepare($query);
        $stmt->bindParam(':id', $id);
        $stmt->execute();
        return $stmt->fetch(PDO::FETCH_ASSOC);
    }
    
    public function create($data) {
        $query = "INSERT INTO " . $this->table . " 
                  (id, name, contact_id, avatar_url, assigned_to, membership_status) 
                  VALUES (:id, :name, :contact_id, :avatar_url, :assigned_to, :membership_status)";
        
        // Generate chat ID
        $chatId = 'CH' . str_pad(rand(100, 999), 3, '0', STR_PAD_LEFT);
        
        $stmt = $this->conn->prepare($query);
        
        $stmt->bindParam(':id', $chatId);
        $stmt->bindParam(':name', $data['name']);
        $stmt->bindParam(':contact_id', $data['contact_id']);
        $stmt->bindParam(':avatar_url', $data['avatar_url']);
        $stmt->bindParam(':assigned_to', $data['assigned_to']);
        $stmt->bindParam(':membership_status', $data['membership_status']);
        
        if ($stmt->execute()) {
            return $chatId;
        }
        
        return false;
    }
    
    public function updateLastMessage($chatId, $message, $time) {
        $query = "UPDATE " . $this->table . " 
                  SET last_message = :message, 
                      last_message_time = :time,
                      updated_at = NOW(),
                      is_unread = 1
                  WHERE id = :id";
        
        $stmt = $this->conn->prepare($query);
        
        $stmt->bindParam(':message', $message);
        $stmt->bindParam(':time', $time);
        $stmt->bindParam(':id', $chatId);
        
        return $stmt->execute();
    }
    
    public function markAsRead($chatId, $userId) {
        $query = "UPDATE " . $this->table . " 
                  SET is_unread = 0 
                  WHERE id = :id AND assigned_to = :user_id";
        
        $stmt = $this->conn->prepare($query);
        
        $stmt->bindParam(':id', $chatId);
        $stmt->bindParam(':user_id', $userId);
        
        return $stmt->execute();
    }
}
?>