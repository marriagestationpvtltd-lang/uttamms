<?php
header("Content-Type: application/json");

$conn = new mysqli("localhost", "ms", "ms", "ms");
if ($conn->connect_error) {
    error_log('user_partner.php: ' . $conn->connect_error);
    die(json_encode(["status"=>"error","message"=>"Database connection failed"]));
}

$data = json_decode(file_get_contents("php://input"), true);
if (!$data) {
    die(json_encode(["status"=>"error","message"=>"Invalid JSON"]));
}

function esc($v,$c){ return $c->real_escape_string($v ?? ''); }

$userid            = esc($data["userid"],$conn);
$minage            = esc($data["minage"],$conn);
$maxage            = esc($data["maxage"],$conn);
$minheight         = esc($data["minheight"],$conn);
$maxheight         = esc($data["maxheight"],$conn);
$maritalstatus     = esc($data["maritalstatus"],$conn);
$profilewithchild  = esc($data["profilewithchild"],$conn);
$familytype        = esc($data["familytype"],$conn);
$religion          = esc($data["religion"],$conn);
$caste             = esc($data["caste"],$conn);
$subcaste          = esc($data["subcaste"],$conn);
$mothertoungue     = esc($data["mothertoungue"],$conn);
$herscopeblief     = esc($data["herscopeblief"],$conn);
$manglik           = esc($data["manglik"],$conn);
$country           = esc($data["country"],$conn);
$state             = esc($data["state"],$conn);
$city              = esc($data["city"],$conn);
$qualification     = esc($data["qualification"],$conn);
$educationmedium   = esc($data["educationmedium"],$conn);
$proffession       = esc($data["proffession"],$conn);
$workingwith       = esc($data["workingwith"],$conn);
$annualincome      = esc($data["annualincome"],$conn);
$diet              = esc($data["diet"],$conn);
$smokeaccept       = esc($data["smokeaccept"],$conn);
$drinkaccept       = esc($data["drinkaccept"],$conn);
$disabilityaccept  = esc($data["disabilityaccept"],$conn);
$complexion        = esc($data["complexion"],$conn);
$bodytype          = esc($data["bodytype"],$conn);
$otherexpectation  = esc($data["otherexpectation"],$conn);

if(!$userid){
    die(json_encode(["status"=>"error","message"=>"userid required"]));
}

$check = $conn->query("SELECT id FROM user_partner WHERE userid='$userid'");

if($check->num_rows>0){
    $sql = "UPDATE user_partner SET
        minage='$minage', maxage='$maxage',
        minheight='$minheight', maxheight='$maxheight',
        maritalstatus='$maritalstatus',
        profilewithchild='$profilewithchild',
        familytype='$familytype',
        religion='$religion',
        caste='$caste',
        subcaste='$subcaste',
        mothertoungue='$mothertoungue',
        herscopeblief='$herscopeblief',
        manglik='$manglik',
        country='$country',
        state='$state',
        city='$city',
        qualification='$qualification',
        educationmedium='$educationmedium',
        proffession='$proffession',
        workingwith='$workingwith',
        annualincome='$annualincome',
        diet='$diet',
        smokeaccept='$smokeaccept',
        drinkaccept='$drinkaccept',
        disabilityaccept='$disabilityaccept',
        complexion='$complexion',
        bodytype='$bodytype',
        otherexpectation='$otherexpectation'
        WHERE userid='$userid'";
}else{
    $sql="INSERT INTO user_partner(
        userid,minage,maxage,minheight,maxheight,maritalstatus,profilewithchild,
        familytype,religion,caste,subcaste,mothertoungue,herscopeblief,manglik,
        country,state,city,qualification,educationmedium,proffession,workingwith,
        annualincome,diet,smokeaccept,drinkaccept,disabilityaccept,complexion,
        bodytype,otherexpectation
    ) VALUES(
        '$userid','$minage','$maxage','$minheight','$maxheight','$maritalstatus',
        '$profilewithchild','$familytype','$religion','$caste','$subcaste',
        '$mothertoungue','$herscopeblief','$manglik','$country','$state','$city',
        '$qualification','$educationmedium','$proffession','$workingwith',
        '$annualincome','$diet','$smokeaccept','$drinkaccept','$disabilityaccept',
        '$complexion','$bodytype','$otherexpectation'
    )";
}

if($conn->query($sql)){
    echo json_encode(["status"=>"success"]);
}else{
    echo json_encode(["status"=>"error","message"=>$conn->error]);
}
