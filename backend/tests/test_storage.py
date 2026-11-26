from datetime import datetime, timezone

from app.services.storage import presign


def test_presign_matches_aws_published_example():
    # "Example: presigned URL" from the AWS docs (Authenticating Requests: Using Query Parameters, SigV4).
    url = presign(
        "GET",
        "examplebucket.s3.amazonaws.com",
        "/test.txt",
        key_id="AKIAIOSFODNN7EXAMPLE",
        secret="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
        region="us-east-1",
        expires=86400,
        now=datetime(2013, 5, 24, tzinfo=timezone.utc),
    )
    assert url.endswith("X-Amz-Signature=aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404")
    assert url.startswith("https://examplebucket.s3.amazonaws.com/test.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256")
