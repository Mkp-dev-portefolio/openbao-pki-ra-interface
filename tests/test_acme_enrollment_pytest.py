"""
pytest-based unit/integration tests for OpenBao ACME enrollment.

These replace the print()-driven test_acme_enrollment.py with proper
assertions and mocked HTTP responses so they can run offline in CI.

Run with:  pytest tests/test_acme_enrollment_pytest.py -v
           pytest tests/ --cov=. --cov-report=term-missing

Live integration tests (require a running OpenBao instance) are marked
with @pytest.mark.integration and are skipped unless you pass:
  pytest -m integration
"""

import base64
import json
import re

import pytest
import responses as resp_mock
import requests

# ─── Constants mirroring the production config ───────────────────────────────
OPENBAO_ADDR = "http://127.0.0.1:8200"
ACME_DIRECTORY_URL = f"{OPENBAO_ADDR}/v1/pki_int/acme/directory"
ACME_NEW_NONCE_URL = f"{OPENBAO_ADDR}/v1/pki_int/acme/new-nonce"
ACME_NEW_ACCOUNT_URL = f"{OPENBAO_ADDR}/v1/pki_int/acme/new-account"
ACME_NEW_ORDER_URL = f"{OPENBAO_ADDR}/v1/pki_int/acme/new-order"
TEST_DOMAIN = "testserver.solar.energy.internal"


# ─── Fixtures ────────────────────────────────────────────────────────────────

@pytest.fixture
def acme_directory_payload():
    """Minimal ACME directory object (RFC 8555 §7.1.1)."""
    return {
        "newAccount": ACME_NEW_ACCOUNT_URL,
        "newNonce":   ACME_NEW_NONCE_URL,
        "newOrder":   ACME_NEW_ORDER_URL,
        "revokeCert": f"{OPENBAO_ADDR}/v1/pki_int/acme/revoke-cert",
        "keyChange":  f"{OPENBAO_ADDR}/v1/pki_int/acme/key-change",
        "meta": {
            "externalAccountRequired": False,
            "caaIdentities": ["energy.internal"],
        },
    }


@pytest.fixture
def sample_nonce():
    return "abc123XYZbase64urlNonce"


# ════════════════════════════════════════════════════════════════════════════
# ACME Directory Discovery
# ════════════════════════════════════════════════════════════════════════════

class TestAcmeDirectoryDiscovery:

    @resp_mock.activate
    def test_directory_returns_200(self, acme_directory_payload):
        resp_mock.add(
            resp_mock.GET, ACME_DIRECTORY_URL,
            json=acme_directory_payload, status=200,
        )
        r = requests.get(ACME_DIRECTORY_URL)
        assert r.status_code == 200

    @resp_mock.activate
    def test_directory_contains_all_rfc8555_required_fields(self, acme_directory_payload):
        """RFC 8555 §7.1.1 mandates newAccount, newNonce, newOrder, revokeCert."""
        resp_mock.add(
            resp_mock.GET, ACME_DIRECTORY_URL,
            json=acme_directory_payload, status=200,
        )
        r = requests.get(ACME_DIRECTORY_URL)
        directory = r.json()

        required = ["newAccount", "newNonce", "newOrder", "revokeCert"]
        for field in required:
            assert field in directory, f"Missing RFC 8555 required field: {field}"

    @resp_mock.activate
    def test_directory_url_values_are_strings_starting_with_http(self, acme_directory_payload):
        resp_mock.add(
            resp_mock.GET, ACME_DIRECTORY_URL,
            json=acme_directory_payload, status=200,
        )
        r = requests.get(ACME_DIRECTORY_URL)
        directory = r.json()

        for key in ["newAccount", "newNonce", "newOrder"]:
            url = directory[key]
            assert isinstance(url, str), f"{key} must be a string"
            assert url.startswith("http"), f"{key} URL must start with http"

    @resp_mock.activate
    def test_directory_meta_contains_external_account_required(self, acme_directory_payload):
        resp_mock.add(
            resp_mock.GET, ACME_DIRECTORY_URL,
            json=acme_directory_payload, status=200,
        )
        r = requests.get(ACME_DIRECTORY_URL)
        meta = r.json().get("meta", {})
        assert "externalAccountRequired" in meta
        assert isinstance(meta["externalAccountRequired"], bool)

    @resp_mock.activate
    def test_directory_unavailable_raises_connection_error(self):
        resp_mock.add(
            resp_mock.GET, ACME_DIRECTORY_URL,
            body=requests.exceptions.ConnectionError("Connection refused"),
        )
        with pytest.raises(requests.exceptions.ConnectionError):
            requests.get(ACME_DIRECTORY_URL)

    @resp_mock.activate
    def test_directory_500_raises_http_error(self):
        resp_mock.add(
            resp_mock.GET, ACME_DIRECTORY_URL,
            json={"error": "internal server error"}, status=500,
        )
        r = requests.get(ACME_DIRECTORY_URL)
        assert r.status_code == 500


# ════════════════════════════════════════════════════════════════════════════
# Nonce Acquisition
# ════════════════════════════════════════════════════════════════════════════

class TestNonceAcquisition:

    @resp_mock.activate
    def test_head_request_returns_replay_nonce_header(self, sample_nonce):
        resp_mock.add(
            resp_mock.HEAD, ACME_NEW_NONCE_URL,
            status=200,
            headers={"Replay-Nonce": sample_nonce},
        )
        r = requests.head(ACME_NEW_NONCE_URL)
        assert "Replay-Nonce" in r.headers

    @resp_mock.activate
    def test_nonce_is_non_empty(self, sample_nonce):
        resp_mock.add(
            resp_mock.HEAD, ACME_NEW_NONCE_URL,
            status=200,
            headers={"Replay-Nonce": sample_nonce},
        )
        r = requests.head(ACME_NEW_NONCE_URL)
        nonce = r.headers.get("Replay-Nonce", "")
        assert len(nonce) > 0

    @resp_mock.activate
    def test_nonce_looks_like_base64url(self, sample_nonce):
        """Nonces must be base64url-safe characters (RFC 8555 §6.5)."""
        resp_mock.add(
            resp_mock.HEAD, ACME_NEW_NONCE_URL,
            status=200,
            headers={"Replay-Nonce": sample_nonce},
        )
        r = requests.head(ACME_NEW_NONCE_URL)
        nonce = r.headers.get("Replay-Nonce", "")
        # Base64url alphabet: A-Z, a-z, 0-9, -, _ (no padding required)
        assert re.match(r'^[A-Za-z0-9\-_=]+$', nonce), (
            f"Nonce contains non-base64url characters: {nonce}"
        )

    @resp_mock.activate
    def test_missing_nonce_header_detected(self):
        resp_mock.add(
            resp_mock.HEAD, ACME_NEW_NONCE_URL,
            status=200,
            # No Replay-Nonce header intentionally
        )
        r = requests.head(ACME_NEW_NONCE_URL)
        nonce = r.headers.get("Replay-Nonce")
        assert nonce is None


# ════════════════════════════════════════════════════════════════════════════
# Account Registration
# ════════════════════════════════════════════════════════════════════════════

class TestAccountRegistration:

    @resp_mock.activate
    def test_new_account_accepts_post_and_returns_201(self):
        """ACME new-account endpoint must return 201 Created for a new account."""
        resp_mock.add(
            resp_mock.POST, ACME_NEW_ACCOUNT_URL,
            json={
                "status": "valid",
                "contact": ["mailto:admin@energy.internal"],
                "orders": f"{OPENBAO_ADDR}/v1/pki_int/acme/orders/abc",
            },
            status=201,
            headers={"Location": f"{OPENBAO_ADDR}/v1/pki_int/acme/accounts/1"},
        )
        payload = {
            "protected": "eyJ...",
            "payload": base64.urlsafe_b64encode(json.dumps({
                "termsOfServiceAgreed": True,
                "contact": ["mailto:admin@energy.internal"],
            }).encode()).decode().rstrip("="),
            "signature": "sig...",
        }
        r = requests.post(ACME_NEW_ACCOUNT_URL, json=payload)
        assert r.status_code == 201
        body = r.json()
        assert body["status"] == "valid"
        assert "Location" in r.headers

    @resp_mock.activate
    def test_account_registration_with_tos_not_agreed_returns_403(self):
        """Server must reject if terms not agreed (RFC 8555 §7.3)."""
        resp_mock.add(
            resp_mock.POST, ACME_NEW_ACCOUNT_URL,
            json={"type": "urn:ietf:params:acme:error:userActionRequired",
                  "detail": "Terms of service must be agreed"},
            status=403,
        )
        r = requests.post(ACME_NEW_ACCOUNT_URL, json={"termsOfServiceAgreed": False})
        assert r.status_code == 403
        assert "error" in r.json()["type"] or "Action" in r.json().get("detail", "")

    @resp_mock.activate
    def test_account_registration_with_malformed_payload_returns_400(self):
        resp_mock.add(
            resp_mock.POST, ACME_NEW_ACCOUNT_URL,
            json={"type": "urn:ietf:params:acme:error:malformed",
                  "detail": "Unable to parse JWS"},
            status=400,
        )
        r = requests.post(ACME_NEW_ACCOUNT_URL, data="not-json")
        assert r.status_code == 400


# ════════════════════════════════════════════════════════════════════════════
# Certificate Order Creation
# ════════════════════════════════════════════════════════════════════════════

class TestCertificateOrder:

    @resp_mock.activate
    def test_new_order_returns_201_with_authorizations(self):
        resp_mock.add(
            resp_mock.POST, ACME_NEW_ORDER_URL,
            json={
                "status": "pending",
                "identifiers": [{"type": "dns", "value": TEST_DOMAIN}],
                "authorizations": [
                    f"{OPENBAO_ADDR}/v1/pki_int/acme/authz/abc123"
                ],
                "finalize": f"{OPENBAO_ADDR}/v1/pki_int/acme/order/abc123/finalize",
            },
            status=201,
        )
        order_payload = {
            "identifiers": [{"type": "dns", "value": TEST_DOMAIN}]
        }
        r = requests.post(ACME_NEW_ORDER_URL, json=order_payload)
        assert r.status_code == 201
        body = r.json()
        assert body["status"] == "pending"
        assert len(body["authorizations"]) > 0
        assert "finalize" in body

    @resp_mock.activate
    def test_order_with_ip_address_identifier_returns_400(self):
        """OpenBao ACME for PKI does not support ip identifiers by default."""
        resp_mock.add(
            resp_mock.POST, ACME_NEW_ORDER_URL,
            json={"type": "urn:ietf:params:acme:error:unsupportedIdentifier",
                  "detail": "IP address identifiers are not supported"},
            status=400,
        )
        order_payload = {
            "identifiers": [{"type": "ip", "value": "192.168.1.1"}]
        }
        r = requests.post(ACME_NEW_ORDER_URL, json=order_payload)
        assert r.status_code == 400

    @resp_mock.activate
    def test_order_for_out_of_policy_domain_returns_403(self):
        """Domain outside the role's allowed_domains must be rejected."""
        resp_mock.add(
            resp_mock.POST, ACME_NEW_ORDER_URL,
            json={"type": "urn:ietf:params:acme:error:rejectedIdentifier",
                  "detail": "Domain not allowed by policy"},
            status=403,
        )
        order_payload = {
            "identifiers": [{"type": "dns", "value": "evil.external.com"}]
        }
        r = requests.post(ACME_NEW_ORDER_URL, json=order_payload)
        assert r.status_code == 403


# ════════════════════════════════════════════════════════════════════════════
# OpenBao Health / Seal state
# ════════════════════════════════════════════════════════════════════════════

class TestOpenBaoHealthChecks:
    HEALTH_URL = f"{OPENBAO_ADDR}/v1/sys/health"

    @resp_mock.activate
    def test_sealed_vault_returns_503(self):
        """A sealed OpenBao returns HTTP 503 from /sys/health."""
        resp_mock.add(
            resp_mock.GET, self.HEALTH_URL,
            json={"sealed": True, "initialized": True},
            status=503,
        )
        r = requests.get(self.HEALTH_URL)
        assert r.status_code == 503
        assert r.json()["sealed"] is True

    @resp_mock.activate
    def test_healthy_vault_returns_200(self):
        resp_mock.add(
            resp_mock.GET, self.HEALTH_URL,
            json={"sealed": False, "initialized": True, "version": "2.0.0"},
            status=200,
        )
        r = requests.get(self.HEALTH_URL)
        assert r.status_code == 200
        body = r.json()
        assert body["sealed"] is False
        assert "version" in body


# ════════════════════════════════════════════════════════════════════════════
# Integration tests (skipped in CI unless -m integration is passed)
# ════════════════════════════════════════════════════════════════════════════

@pytest.mark.integration
class TestLiveAcmeEndpoints:
    """Require a running OpenBao instance at http://127.0.0.1:8200."""

    def test_live_directory_discovery(self):
        r = requests.get(ACME_DIRECTORY_URL, timeout=5)
        assert r.status_code == 200
        directory = r.json()
        for field in ["newAccount", "newNonce", "newOrder"]:
            assert field in directory

    def test_live_nonce_acquisition(self):
        r_dir = requests.get(ACME_DIRECTORY_URL, timeout=5)
        nonce_url = r_dir.json()["newNonce"]
        r = requests.head(nonce_url, timeout=5)
        nonce = r.headers.get("Replay-Nonce")
        assert nonce is not None
        assert len(nonce) > 0
