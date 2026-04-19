<?php
namespace App\Models;

use PDO;

class Profile {
    private $conn;
    private $table = 'ac_memorial_profiles';
    
    public function __construct($db) {
        $this->conn = $db;
    }
    
    public function getAll($search = '', $filter = 'all', $page = 1, $perPage = 10) {
        $offset = ($page - 1) * $perPage;
        
        $query = "SELECT * FROM " . $this->table . " WHERE 1=1";
        $params = [];
        
        if (!empty($search)) {
            $query .= " AND (name LIKE :search OR id LIKE :search)";
            $params[':search'] = "%$search%";
        }
        
        if ($filter !== 'all') {
            $query .= " AND membership_status = :status";
            $params[':status'] = $filter;
        }
        
        $query .= " LIMIT :limit OFFSET :offset";
        $params[':limit'] = $perPage;
        $params[':offset'] = $offset;
        
        $stmt = $this->conn->prepare($query);
        
        foreach ($params as $key => $value) {
            $stmt->bindValue($key, $value, is_int($value) ? PDO::PARAM_INT : PDO::PARAM_STR);
        }
        
        $stmt->execute();
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
    
    public function getCount($search = '', $filter = 'all') {
        $query = "SELECT COUNT(*) as total FROM " . $this->table . " WHERE 1=1";
        $params = [];
        
        if (!empty($search)) {
            $query .= " AND (name LIKE :search OR id LIKE :search)";
            $params[':search'] = "%$search%";
        }
        
        if ($filter !== 'all') {
            $query .= " AND membership_status = :status";
            $params[':status'] = $filter;
        }
        
        $stmt = $this->conn->prepare($query);
        $stmt->execute($params);
        $result = $stmt->fetch(PDO::FETCH_ASSOC);
        
        return $result['total'] ?? 0;
    }
    
    public function share($chatId, $profileId, $userId) {
        $query = "INSERT INTO ac_profile_shares (chat_id, profile_id, shared_by, status) 
                  VALUES (:chat_id, :profile_id, :shared_by, 'sent')";
        
        $stmt = $this->conn->prepare($query);
        
        $stmt->bindParam(':chat_id', $chatId);
        $stmt->bindParam(':profile_id', $profileId);
        $stmt->bindParam(':shared_by', $userId);
        
        if ($stmt->execute()) {
            return $this->conn->lastInsertId();
        }
        
        return false;
    }
    
    public function updateStatus($profileId, $userId, $status) {
        $query = "UPDATE ac_profile_shares 
                  SET status = :status 
                  WHERE profile_id = :profile_id AND shared_by = :user_id";
        
        $stmt = $this->conn->prepare($query);
        
        $stmt->bindParam(':status', $status);
        $stmt->bindParam(':profile_id', $profileId);
        $stmt->bindParam(':user_id', $userId);
        
        return $stmt->execute();
    }
}
?>