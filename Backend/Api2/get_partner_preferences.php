<?php
header("Content-Type: application/json");

$conn = new mysqli("localhost", "ms", "ms", "ms");
if ($conn->connect_error) {
    error_log('get_partner_preferences.php: ' . $conn->connect_error);
    die(json_encode(["status" => "error", "message" => "Database connection failed"]));
}

// Handle both GET and POST requests
$userid = '';

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $userid = isset($_GET['userid']) ? $conn->real_escape_string($_GET['userid']) : '';
} else {
    $data = json_decode(file_get_contents("php://input"), true);
    if ($data) {
        $userid = isset($data['userid']) ? $conn->real_escape_string($data['userid']) : '';
    }
}

if (empty($userid)) {
    die(json_encode(["status" => "error", "message" => "userid required"]));
}

// Query to get partner preferences
$sql = "SELECT * FROM user_partner WHERE userid = '$userid'";
$result = $conn->query($sql);

if ($result && $result->num_rows > 0) {
    $row = $result->fetch_assoc();
    
    // Function to get country names from IDs
    function getCountryNames($conn, $ids) {
        if (empty($ids) || $ids == '0') return ['Any'];
        $idArray = explode(',', $ids);
        $names = [];
        foreach ($idArray as $id) {
            if ($id == '0') {
                $names[] = 'Any';
            } else {
                $countryResult = $conn->query("SELECT name FROM countries WHERE id = '$id'");
                if ($countryResult && $countryResult->num_rows > 0) {
                    $countryRow = $countryResult->fetch_assoc();
                    $names[] = $countryRow['name'];
                } else {
                    $names[] = $id; // Fallback to ID if not found
                }
            }
        }
        return $names;
    }
    
    // Function to get state names from IDs (table name is 'state')
    function getStateNames($conn, $ids) {
        if (empty($ids) || $ids == '0') return ['Any'];
        $idArray = explode(',', $ids);
        $names = [];
        foreach ($idArray as $id) {
            if ($id == '0') {
                $names[] = 'Any';
            } else {
                $stateResult = $conn->query("SELECT name FROM state WHERE id = '$id'");
                if ($stateResult && $stateResult->num_rows > 0) {
                    $stateRow = $stateResult->fetch_assoc();
                    $names[] = $stateRow['name'];
                } else {
                    $names[] = $id; // Fallback to ID if not found
                }
            }
        }
        return $names;
    }
    
    // Function to get district/city names from IDs (table name is 'districts')
    function getDistrictNames($conn, $ids) {
        if (empty($ids) || $ids == '0') return ['Any'];
        $idArray = explode(',', $ids);
        $names = [];
        foreach ($idArray as $id) {
            if ($id == '0') {
                $names[] = 'Any';
            } else {
                $districtResult = $conn->query("SELECT name FROM districts WHERE id = '$id'");
                if ($districtResult && $districtResult->num_rows > 0) {
                    $districtRow = $districtResult->fetch_assoc();
                    $names[] = $districtRow['name'];
                } else {
                    $names[] = $id; // Fallback to ID if not found
                }
            }
        }
        return $names;
    }
    
    // Get names for location fields
    $countryNames = getCountryNames($conn, $row['country']);
    $stateNames = getStateNames($conn, $row['state']);
    $districtNames = getDistrictNames($conn, $row['city']); // city column stores district IDs
    
    // Also return the IDs for reference (useful for loading dependent dropdowns)
    $countryIds = explode(',', $row['country']);
    $stateIds = explode(',', $row['state']);
    $districtIds = explode(',', $row['city']);
    
    $response = [
        "status" => "success",
        "data" => [
            "userid" => $row['userid'],
            "minage" => $row['minage'],
            "maxage" => $row['maxage'],
            "minheight" => $row['minheight'],
            "maxheight" => $row['maxheight'],
            "maritalstatus" => explode(',', $row['maritalstatus']),
            "profilewithchild" => $row['profilewithchild'],
            "familytype" => explode(',', $row['familytype']),
            "religion" => explode(',', $row['religion']),
            "caste" => explode(',', $row['caste']),
            "subcaste" => explode(',', $row['subcaste']),
            "mothertoungue" => explode(',', $row['mothertoungue']),
            "herscopeblief" => $row['herscopeblief'],
            "manglik" => $row['manglik'],
            "country" => $countryNames, // Returns country names
            "country_ids" => $countryIds, // Optional: keep IDs if needed
            "state" => $stateNames, // Returns state names
            "state_ids" => $stateIds, // Optional: keep IDs if needed
            "city" => $districtNames, // Returns district names (from districts table)
            "city_ids" => $districtIds, // Optional: keep district IDs if needed
            "qualification" => explode(',', $row['qualification']),
            "educationmedium" => explode(',', $row['educationmedium']),
            "proffession" => explode(',', $row['proffession']),
            "workingwith" => explode(',', $row['workingwith']),
            "annualincome" => explode(',', $row['annualincome']),
            "diet" => explode(',', $row['diet']),
            "smokeaccept" => $row['smokeaccept'],
            "drinkaccept" => $row['drinkaccept'],
            "disabilityaccept" => $row['disabilityaccept'],
            "complexion" => explode(',', $row['complexion']),
            "bodytype" => explode(',', $row['bodytype']),
            "otherexpectation" => $row['otherexpectation']
        ]
    ];
    
    echo json_encode($response);
} else {
    echo json_encode([
        "status" => "success", 
        "data" => null,
        "message" => "No data found for this user"
    ]);
}

$conn->close();
?>