import configparser
import itertools
import json
import logging
import os
import sys
import time
from pathlib import Path
from typing import Union

import oci
import paramiko
from dotenv import load_dotenv
import requests

# Load environment variables from .env file
load_dotenv('oci.env')

ARM_SHAPE = "VM.Standard.A1.Flex"
E2_MICRO_SHAPE = "VM.Standard.E2.1.Micro"

# Access loaded environment variables and strip white spaces
OCI_CONFIG = os.getenv("OCI_CONFIG", "").strip()
OCT_FREE_AD = os.getenv("OCT_FREE_AD", "").strip()
DISPLAY_NAME = os.getenv("DISPLAY_NAME", "").strip()
try:
    WAIT_TIME = int(os.getenv("REQUEST_WAIT_TIME_SECS", "90").strip() or "90")
except ValueError:
    print("[CONFIG ERROR] REQUEST_WAIT_TIME_SECS 는 정수여야 합니다.", file=sys.stderr)
    sys.exit(1)
SSH_AUTHORIZED_KEYS_FILE = os.getenv("SSH_AUTHORIZED_KEYS_FILE", "").strip()
OCI_IMAGE_ID = os.getenv("OCI_IMAGE_ID", None).strip() if os.getenv("OCI_IMAGE_ID") else None
OCI_COMPUTE_SHAPE = os.getenv("OCI_COMPUTE_SHAPE", ARM_SHAPE).strip()
SECOND_MICRO_INSTANCE = os.getenv("SECOND_MICRO_INSTANCE", 'False').strip().lower() == 'true'
OCI_SUBNET_ID = os.getenv("OCI_SUBNET_ID", None).strip() if os.getenv("OCI_SUBNET_ID") else None
OPERATING_SYSTEM = os.getenv("OPERATING_SYSTEM", "").strip()
OS_VERSION = os.getenv("OS_VERSION", "").strip()
ASSIGN_PUBLIC_IP = os.getenv("ASSIGN_PUBLIC_IP", "false").strip()
BOOT_VOLUME_SIZE = os.getenv("BOOT_VOLUME_SIZE", "50").strip()
DISCORD_WEBHOOK = os.getenv("DISCORD_WEBHOOK", "").strip()
OCI_REGIONS = os.getenv("OCI_REGIONS", "").strip()

ERROR_LOG_PATH = Path("ERROR_IN_CONFIG.log")


def _abort_with_config_error(message: str) -> None:
    """OCI Config 관련 오류를 ERROR_IN_CONFIG.log 에 기록하고 즉시 종료."""
    ERROR_LOG_PATH.write_text(message, encoding="utf-8")
    print(f"[CONFIG ERROR] {message}", file=sys.stderr)
    sys.exit(1)


# OCI Config 파일 사전 검증 (configparser.read 는 파일 부재 시에도 silent fail 함)
if not OCI_CONFIG:
    _abort_with_config_error(
        "oci.env 의 OCI_CONFIG 가 비어있습니다.\n"
        "1) cp oci.env.example oci.env\n"
        "2) oci.env 의 OCI_CONFIG 에 OCI API config 파일의 절대 경로를 지정하세요."
    )

oci_config_file = Path(OCI_CONFIG).expanduser()
if not oci_config_file.is_file():
    _abort_with_config_error(
        f"OCI_CONFIG 경로의 파일을 찾을 수 없습니다: {oci_config_file}\n"
        "절대 경로인지, 파일이 실제로 존재하는지, 읽기 권한이 있는지 확인하세요."
    )

config = configparser.ConfigParser()
try:
    read_files = config.read(oci_config_file)
    if not read_files:
        _abort_with_config_error(
            f"OCI Config 파일을 읽지 못했습니다: {oci_config_file}\n"
            "파일 권한 또는 인코딩(UTF-8)을 확인하세요."
        )

    try:
        OCI_USER_ID = config.get("DEFAULT", "user")
    except configparser.NoOptionError:
        _abort_with_config_error(
            f"OCI Config 파일에 [DEFAULT] 의 user= 항목이 없습니다: {oci_config_file}\n"
            "sample_oci_config 형식을 참고해 user/fingerprint/tenancy/region/key_file 을 채우세요."
        )

    if OCI_COMPUTE_SHAPE not in (ARM_SHAPE, E2_MICRO_SHAPE):
        _abort_with_config_error(
            f"OCI_COMPUTE_SHAPE 값이 올바르지 않습니다: {OCI_COMPUTE_SHAPE}\n"
            f"허용값: {ARM_SHAPE} 또는 {E2_MICRO_SHAPE}"
        )

    env_has_spaces = any(
        isinstance(confg_var, str) and " " in confg_var
        for confg_var in [OCI_CONFIG, OCT_FREE_AD, SSH_AUTHORIZED_KEYS_FILE,
                          OCI_IMAGE_ID, OCI_COMPUTE_SHAPE, OCI_SUBNET_ID,
                          OS_VERSION, DISCORD_WEBHOOK]
    )
    config_has_spaces = any(
        " " in value
        for section in config.sections()
        for _, value in config.items(section)
    )
    if env_has_spaces:
        _abort_with_config_error("oci.env 값에 공백이 포함돼 있습니다. 공백을 제거하세요.")
    if config_has_spaces:
        _abort_with_config_error("oci_config 값에 공백이 포함돼 있습니다. 공백을 제거하세요.")

except configparser.Error as e:
    _abort_with_config_error(f"OCI Config 파싱 오류: {e}")

# 정상 진입 시점 -- 이전 실행에서 남은 stale 에러 로그 정리
if ERROR_LOG_PATH.exists():
    ERROR_LOG_PATH.unlink()

# Set up logging
logging.basicConfig(
    filename="setup_and_info.log",
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s",
)
logging_step5 = logging.getLogger("launch_instance")
logging_step5.setLevel(logging.INFO)
fh = logging.FileHandler("launch_instance.log")
fh.setFormatter(logging.Formatter("%(asctime)s - %(levelname)s - %(message)s"))
logging_step5.addHandler(fh)

# Set up OCI Config and Clients
oci_config_path = str(oci_config_file)
config = oci.config.from_file(oci_config_path)
iam_client = oci.identity.IdentityClient(config)
network_client = oci.core.VirtualNetworkClient(config)
compute_client = oci.core.ComputeClient(config)

IMAGE_LIST_KEYS = [
    "lifecycle_state",
    "display_name",
    "id",
    "operating_system",
    "operating_system_version",
    "size_in_mbs",
    "time_created",
]


def write_into_file(file_path, data):
    """Write data into a file.

    Args:
        file_path (str): The path of the file.
        data (str): The data to be written into the file.
    """
    with open(file_path, mode="a", encoding="utf-8") as file_writer:
        file_writer.write(data)


def list_all_instances(compartment_id):
    """Retrieve a list of all instances in the specified compartment.

    Args:
        compartment_id (str): The compartment ID.

    Returns:
        list: The list of instances returned from the OCI service.
    """
    list_instances_response = compute_client.list_instances(compartment_id=compartment_id)
    return list_instances_response.data


def create_instance_details_file_and_notify(instance, shape=ARM_SHAPE):
    """Create a file with details of instances and notify the user.

    Args:
        instance (dict): The instance dictionary returned from the OCI service.
        shape (str): shape of the instance to be created, acceptable values are
         "VM.Standard.A1.Flex", "VM.Standard.E2.1.Micro"
    """
    details = [f"Instance ID: {instance.id}",
               f"Display Name: {instance.display_name}",
               f"Availability Domain: {instance.availability_domain}",
               f"Shape: {instance.shape}",
               f"State: {instance.lifecycle_state}",
               "\n"]
    micro_body = 'TWo Micro Instances are already existing and running'
    arm_body = '\n'.join(details)
    body = arm_body if shape == ARM_SHAPE else micro_body
    write_into_file('INSTANCE_CREATED', body)

    # Discord notification with instance details
    discord_body = (
        f"**OCI ARM 인스턴스 생성 성공!**\n"
        f"```\n"
        f"인스턴스 ID : {instance.id}\n"
        f"이름        : {instance.display_name}\n"
        f"가용 도메인 : {instance.availability_domain}\n"
        f"Shape       : {instance.shape}\n"
        f"상태        : {instance.lifecycle_state}\n"
        f"```"
    )
    send_discord_message(discord_body)


def notify_on_failure(failure_msg):
    """Notifies users when the Instance Creation Failed due to an error that's
    not handled.

    Args:
        failure_msg (msg): The error message.
    """

    log_body = (
        "스크립트가 예외로 인해 비정상 종료되었습니다.\n\n"
        "재실행: ./setup_init.sh rerun\n\n"
        "문제가 지속되면 아래 저장소에 이슈를 등록해 주세요:\n"
        "https://github.com/kim62210/automate-oracle-instance/issues\n\n"
        "에러 메시지:\n\n"
        f"{failure_msg}"
    )
    write_into_file('UNHANDLED_ERROR.log', log_body)
    send_discord_message(f"**OCI 스크립트 비정상 종료**\n```\n{failure_msg[:1800]}\n```")


def check_instance_state_and_write(compartment_id, shape, states=('RUNNING', 'PROVISIONING'),
                                   tries=3):
    """Check the state of instances in the specified compartment and take action when a matching instance is found.

    Args:
        compartment_id (str): The compartment ID to check for instances.
        shape (str): The shape of the instance.
        states (tuple, optional): The lifecycle states to consider. Defaults to ('RUNNING', 'PROVISIONING').
        tries(int, optional): No of reties until an instance is found. Defaults to 3.

    Returns:
        bool: True if a matching instance is found, False otherwise.
    """
    for _ in range(tries):
        instance_list = list_all_instances(compartment_id=compartment_id)
        if shape == ARM_SHAPE:
            running_arm_instance = next((instance for instance in instance_list if
                                         instance.shape == shape and instance.lifecycle_state in states), None)
            if running_arm_instance:
                create_instance_details_file_and_notify(running_arm_instance, shape)
                return True
        else:
            micro_instance_list = [instance for instance in instance_list if
                                   instance.shape == shape and instance.lifecycle_state in states]
            if len(micro_instance_list) > 1 and SECOND_MICRO_INSTANCE:
                create_instance_details_file_and_notify(micro_instance_list[-1], shape)
                return True
            if len(micro_instance_list) == 1 and not SECOND_MICRO_INSTANCE:
                create_instance_details_file_and_notify(micro_instance_list[-1], shape)
                return True       
        if tries - 1 > 0:
            time.sleep(60)

    return False


def handle_errors(command, data, log):
    """Handles errors and logs messages.

    Args:
        command (arg): The OCI command being executed.
        data (dict): The data or error information returned from the OCI service.
        log (logging.Logger): The logger instance for logging messages.

    Returns:
        bool: True if the error is temporary and the operation should be retried after a delay.
        Raises Exception for unexpected errors.
    """

    # Check for temporary errors that can be retried
    if "code" in data:
        if (data["code"] in ("TooManyRequests", "Out of host capacity.", 'InternalError')) \
                or (data["message"] in ("Out of host capacity.", "Bad Gateway")):
            handle_errors.retry_count = getattr(handle_errors, 'retry_count', 0) + 1
            if not hasattr(handle_errors, 'error_stats'):
                handle_errors.error_stats = {}
                handle_errors.start_time = time.time()
            error_key = data.get("message") or data.get("code")
            handle_errors.error_stats[error_key] = handle_errors.error_stats.get(error_key, 0) + 1
            count = handle_errors.retry_count
            if count % 10 == 0:
                elapsed = int((time.time() - handle_errors.start_time) / 60)
                stats_lines = '\n'.join(
                    f"  {k}: {v}회" for k, v in handle_errors.error_stats.items()
                )
                send_discord_message(
                    f"**[{count}회 재시도 / {elapsed}분 경과]**\n"
                    f"```\n{stats_lines}\n```"
                )
            log.info("Command: %s--\nOutput: %s (retry #%d)", command, data, count)
            time.sleep(WAIT_TIME)
            return True

    if "status" in data and data["status"] == 502:
        handle_errors.retry_count = getattr(handle_errors, 'retry_count', 0) + 1
        if not hasattr(handle_errors, 'error_stats'):
            handle_errors.error_stats = {}
            handle_errors.start_time = time.time()
        handle_errors.error_stats["502 Bad Gateway"] = handle_errors.error_stats.get("502 Bad Gateway", 0) + 1
        count = handle_errors.retry_count
        if count % 10 == 0:
            elapsed = int((time.time() - handle_errors.start_time) / 60)
            stats_lines = '\n'.join(
                f"  {k}: {v}회" for k, v in handle_errors.error_stats.items()
            )
            send_discord_message(
                f"**[{count}회 재시도 / {elapsed}분 경과]**\n"
                f"```\n{stats_lines}\n```"
            )
        log.info("Command: %s~~\nOutput: %s (retry #%d)", command, data, count)
        time.sleep(WAIT_TIME)
        return True
    failure_msg = '\n'.join([f'{key}: {value}' for key, value in data.items()])
    notify_on_failure(failure_msg)
    # Raise an exception for unexpected errors
    raise Exception("Error: %s" % data)


def execute_oci_command(client, method, *args, **kwargs):
    """Executes an OCI command using the specified OCI client.

    Args:
        client: The OCI client instance.
        method (str): The method to call on the OCI client.
        args: Additional positional arguments to pass to the OCI client method.
        kwargs: Additional keyword arguments to pass to the OCI client method.

    Returns:
        dict: The data returned from the OCI service.

    Raises:
        Exception: Raises an exception if an unexpected error occurs.
    """
    while True:
        try:
            response = getattr(client, method)(*args, **kwargs)
            data = response.data if hasattr(response, "data") else response
            return data
        except oci.exceptions.ServiceError as srv_err:
            data = {"status": srv_err.status,
                    "code": srv_err.code,
                    "message": srv_err.message}
            handle_errors(args, data, logging_step5)


def generate_ssh_key_pair(public_key_file: Union[str, Path], private_key_file: Union[str, Path]):
    """Generates an SSH key pair and saves them to the specified files.

    Args:
        public_key_file :file to save the public key.
        private_key_file : The file to save the private key.
    """
    key = paramiko.RSAKey.generate(2048)
    key.write_private_key_file(private_key_file)
    # Save public key to file
    write_into_file(public_key_file, (f"ssh-rsa {key.get_base64()} "
                                      f"{Path(public_key_file).stem}_auto_generated"))


def read_or_generate_ssh_public_key(public_key_file: Union[str, Path]):
    """Reads the SSH public key from the file if it exists, else generates and reads it.

    Args:
        public_key_file: The file containing the public key.

    Returns:
        Union[str, Path]: The SSH public key.
    """
    public_key_path = Path(public_key_file)

    if not public_key_path.is_file():
        logging.info("SSH key doesn't exist... Generating SSH Key Pair")
        public_key_path.parent.mkdir(parents=True, exist_ok=True)
        private_key_path = public_key_path.with_name(f"{public_key_path.stem}_private")
        generate_ssh_key_pair(public_key_path, private_key_path)

    with open(public_key_path, "r", encoding="utf-8") as pub_key_file:
        ssh_public_key = pub_key_file.read()

    return ssh_public_key


def send_discord_message(message):
    """Send a message to Discord using the webhook URL if available."""
    if DISCORD_WEBHOOK:
        payload = {"content": message}
        try:
            response = requests.post(DISCORD_WEBHOOK, json=payload)
            response.raise_for_status()
        except requests.RequestException as e:
            logging.error("Failed to send Discord message: %s", e)


def setup_region_target(region_name, base_oci_config, compartment_id):
    """Prepare compute resources for a specific OCI region.

    Returns:
        dict with region/compute_client/ad_name/subnet_id/image_id, or None if setup fails.
    """
    region_config = dict(base_oci_config)
    region_config["region"] = region_name

    try:
        region_iam = oci.identity.IdentityClient(region_config)
        region_network = oci.core.VirtualNetworkClient(region_config)
        region_compute = oci.core.ComputeClient(region_config)

        # AD
        ads = region_iam.list_availability_domains(compartment_id=compartment_id).data
        if not ads:
            logging.warning("Region %s: AD not found, skipping", region_name)
            return None

        # Subnet -- use env var if set and region matches base config, else auto-discover
        subnet_id = None
        if OCI_SUBNET_ID and region_name == base_oci_config.get("region"):
            subnet_id = OCI_SUBNET_ID
        else:
            subnets = region_network.list_subnets(compartment_id=compartment_id).data
            public_subnets = [s for s in subnets if not s.prohibit_public_ip_on_vnic]
            if public_subnets:
                subnet_id = public_subnets[0].id
            elif subnets:
                subnet_id = subnets[0].id

        if not subnet_id:
            logging.warning("Region %s: no subnet found, skipping", region_name)
            return None

        # Image -- use env var if set and region matches base config, else auto-discover
        image_id = None
        if OCI_IMAGE_ID and region_name == base_oci_config.get("region"):
            image_id = OCI_IMAGE_ID
        else:
            images = region_compute.list_images(
                compartment_id=compartment_id,
                shape=OCI_COMPUTE_SHAPE,
            ).data
            image_id = next(
                (img.id for img in images
                 if img.operating_system == OPERATING_SYSTEM
                 and img.operating_system_version == OS_VERSION),
                None,
            )

        if not image_id:
            logging.warning("Region %s: no matching image (%s %s), skipping",
                            region_name, OPERATING_SYSTEM, OS_VERSION)
            return None

        return {
            "region": region_name,
            "compute_client": region_compute,
            "ad_name": ads[0].name,
            "subnet_id": subnet_id,
            "image_id": image_id,
        }
    except oci.exceptions.ServiceError as e:
        logging.warning("Region %s: setup failed - %s", region_name, e.message)
        return None


def launch_instance():
    """Launches an OCI Compute instance using the specified parameters.

    Raises:
        Exception: Raises an exception if an unexpected error occurs.
    """
    # Step 1 - Get TENANCY
    user_info = execute_oci_command(iam_client, "get_user", OCI_USER_ID)
    oci_tenancy = user_info.compartment_id
    logging.info("OCI_TENANCY: %s", oci_tenancy)

    # Step 2 - Set up region targets
    base_oci_config = oci.config.from_file(oci_config_path)
    regions = ([r.strip() for r in OCI_REGIONS.split(",") if r.strip()]
               if OCI_REGIONS else [base_oci_config["region"]])

    targets = []
    for region in regions:
        target = setup_region_target(region, base_oci_config, oci_tenancy)
        if target:
            targets.append(target)
            logging.info("Region %s ready: AD=%s, subnet=%s, image=%s",
                         region, target["ad_name"], target["subnet_id"], target["image_id"])
        else:
            logging.warning("Region %s: skipped (resource discovery failed)", region)

    if not targets:
        send_discord_message("유효한 리전 타겟이 없습니다. oci.env 설정을 확인하세요.")
        raise Exception("No valid region targets found")

    target_cycle = itertools.cycle(targets)
    region_names = ", ".join(t["region"] for t in targets)
    logging.info("Targeting %d region(s): %s", len(targets), region_names)

    assign_public_ip = ASSIGN_PUBLIC_IP.lower() in ["true", "1", "y", "yes"]
    boot_volume_size = max(50, int(BOOT_VOLUME_SIZE))
    ssh_public_key = read_or_generate_ssh_public_key(SSH_AUTHORIZED_KEYS_FILE)

    # Step 3 - Launch Instance loop
    if OCI_COMPUTE_SHAPE == "VM.Standard.A1.Flex":
        shape_config = oci.core.models.LaunchInstanceShapeConfigDetails(ocpus=4, memory_in_gbs=24)
    else:
        shape_config = oci.core.models.LaunchInstanceShapeConfigDetails(ocpus=1, memory_in_gbs=1)

    retry_count = 0
    # {region: {error_code: count}} 형태로 리전별 에러 수집
    region_error_stats = {}
    start_time = time.time()

    while True:
        target = next(target_cycle)
        retry_count += 1
        try:
            launch_instance_response = target["compute_client"].launch_instance(
                launch_instance_details=oci.core.models.LaunchInstanceDetails(
                    availability_domain=target["ad_name"],
                    compartment_id=oci_tenancy,
                    create_vnic_details=oci.core.models.CreateVnicDetails(
                        assign_public_ip=assign_public_ip,
                        assign_private_dns_record=True,
                        display_name=DISPLAY_NAME,
                        subnet_id=target["subnet_id"],
                    ),
                    display_name=DISPLAY_NAME,
                    shape=OCI_COMPUTE_SHAPE,
                    availability_config=oci.core.models.LaunchInstanceAvailabilityConfigDetails(
                        recovery_action="RESTORE_INSTANCE"
                    ),
                    instance_options=oci.core.models.InstanceOptions(
                        are_legacy_imds_endpoints_disabled=False
                    ),
                    shape_config=shape_config,
                    source_details=oci.core.models.InstanceSourceViaImageDetails(
                        source_type="image",
                        image_id=target["image_id"],
                        boot_volume_size_in_gbs=boot_volume_size,
                    ),
                    metadata={
                        "ssh_authorized_keys": ssh_public_key},
                )
            )
            if launch_instance_response.status == 200:
                instance = launch_instance_response.data
                logging_step5.info("[%s] Instance created: %s", target["region"], instance.id)
                create_instance_details_file_and_notify(instance, OCI_COMPUTE_SHAPE)
                return

        except oci.exceptions.ServiceError as srv_err:
            region = target["region"]
            error_code = srv_err.code or "Unknown"
            if region not in region_error_stats:
                region_error_stats[region] = {}
            region_error_stats[region][error_code] = region_error_stats[region].get(error_code, 0) + 1

            if srv_err.code == "LimitExceeded":
                logging_step5.info("LimitExceeded - 이미 인스턴스 존재 가능. 종료.")
                send_discord_message("LimitExceeded - 이미 인스턴스가 존재하거나 한도 초과. 스크립트 종료.")
                return

            logging_step5.info("retry #%d [%s] | %s: %s",
                               retry_count, region, srv_err.code, srv_err.message)

            if retry_count % 10 == 0:
                elapsed = int((time.time() - start_time) / 60)
                lines = []
                for rgn, errors in region_error_stats.items():
                    lines.append(f"-- {rgn} --")
                    for code, cnt in errors.items():
                        lines.append(f"  {code}: {cnt}회")
                stats_block = '\n'.join(lines)
                send_discord_message(
                    f"**[{retry_count}회 재시도 / {elapsed}분 경과]**\n"
                    f"```\n{stats_block}\n```"
                )

        time.sleep(WAIT_TIME)


if __name__ == "__main__":
    region_list = OCI_REGIONS if OCI_REGIONS else config.get("region", "unknown")
    send_discord_message(f"OCI ARM 인스턴스 생성 스크립트 시작 (리전: {region_list}, {WAIT_TIME}초 간격 재시도)")
    try:
        launch_instance()
        send_discord_message("OCI ARM 인스턴스 생성 완료!")
    except Exception as e:
        error_message = f"OCI 스크립트 오류 발생:\n{str(e)}"
        send_discord_message(error_message)
        raise
