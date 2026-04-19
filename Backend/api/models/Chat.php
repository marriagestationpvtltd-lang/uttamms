<?php
class Chat {
    private $conn;
    private $table = 'ac_chats';
    
    public function __construct() {
        $database = new Database();
        $this->conn = $database->connect();
    }
    
    public function getUserChats($userId, $search = '', $filter = 'all') {
        $query = "SELECT 
                    c.id,
                    c.name,
                    c.avatar_url,
                    c.last_message,
                    c.last_message_time as time,
                    c.is_pinned,
                    c.is_unread,
                    c.is_group,
                    c.has_file,
                    c.membership_status,
                    COUNT(DISTINCT ps.id) as shared_profiles_count
                  FROM {$this->table} c
                  LEFT JOIN ac_profile_shares ps ON c.id = ps.chat_id
                  WHERE c.assigned_to = :user_id";
        
        $params = [':user_id' => $userId];
        
        if (!empty($search)) {
            $query .= " AND (c.name LIKE :search OR c.last_message LIKE :search)";
            $params[':search'] = "%$search%";
        }
        
        if ($filter === 'unread') {
            $query .= " AND c.is_unread = 1";
        } elseif ($filter === 'pinned') {
            $query .= " AND c.is_pinned = 1";
        }
        
        $query .= " GROUP BY c.id ORDER BY c.is_pinned DESC, c.updated_at DESC";
        
        $stmt = $this->conn->prepare($query);
        $stmt->execute($params);
        
        return $stmt->fetchAll(PDO::FETCH_ASSOC);
    }
    
    public function findById($chatId) {
        $query = "SELECT * FROM {$this->table} WHERE id = :id";
        $stmt = $this->conn->prepare($query);
        $stmt->execute([':id' => $chatId]);
        
        return $stmt->fetch(PDO::FETCH_ASSOC);
    }
    
    public function create($data) {
        $query = "INSERT INTO {$this->table} 
                  (id, name, contact_id, avatar_url, assigned_to, membership_status) 
                  VALUES (:id, :name, :contact_id, :avatar_url, :assigned_to, :membership_status)";
        
        // Generate chat ID
        $chatId = 'CH' . str_pad(rand(100, 999), 3, '0', STR_PAD_LEFT);
        
        $stmt = $this->conn->prepare($query);
        $stmt->execute([
            ':id' => $chatId,
            ':name' => $data['name'],
            ':contact_id' => $data['contact_id'],
            ':avatar_url' => $data['avatar_url'],
            ':assigned_to' => $data['assigned_to'],
            ':membership_status' => $data['membership_status']
        ]);
        
        return $chatId;
    }
    
    public function updateLastMessage($chatId, $message, $time) {
        $query = "UPDATE {$this->table} 
                  SET last_message = :message, 
                      last_message_time = :time,
                      updated_at = NOW(),
                      is_unread = 1
                  WHERE id = :id";
        
        $stmt = $this->conn->prepare($query);
        return $stmt->execute([
            ':message' => $message,
            ':time' => $time,
            ':id' => $chatId
        ]);
    }
    
    public function markAsRead($chatId, $userId) {
        $query = "UPDATE {$this->table} 
                  SET is_unread = 0 
                  WHERE id = :id AND assigned_to = :user_id";
        
        $stmt = $this->conn->prepare($query);
        return $stmt->execute([
            ':id' => $chatId,
            ':user_id' => $userId
        ]);
    }
}
?>