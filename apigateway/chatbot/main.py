import functions_framework
import openai
from google.cloud import secretmanager  # type:ignore

from infra import auth  # type:ignore
from infra.config import project_id  # type:ignore
from infra.proxies.proxy_base import check_crc  # type:ignore

api_key = "openai_api_key"
org_id = "openai_org_id"


def _get_credentials() -> tuple:
    client = secretmanager.SecretManagerServiceClient()

    # Access the secret version.
    api_key_response = client.access_secret_version(
        request={
            "name": f"projects/{project_id}/secrets/{api_key}/versions/latest"
        }
    )
    org_id_response = client.access_secret_version(
        request={
            "name": f"projects/{project_id}/secrets/{org_id}/versions/latest"
        }
    )

    check_crc(api_key_response)
    check_crc(org_id_response)
    return (
        api_key_response.payload.data.decode("UTF-8"),
        org_id_response.payload.data.decode("UTF-8"),
    )


@functions_framework.http
@auth
def chatbot(request):
    """Implement POST /v1/chatbot"""

    # Validate inputs
    payload = request.get_json() if request.is_json else None

    if not payload or not (question := payload.get("question")):
        return ("Missing or invalid payload", 400)

    openai.api_key, openai.organization = _get_credentials()

    chat_completion = openai.ChatCompletion.create(
        model="gpt-3.5-turbo",
        messages=[{"role": "user", "content": f"{question}"}],
    )
    answer = chat_completion.choices[0].message.content
    payload: dict = {"answer": answer}

    return (payload, 200)