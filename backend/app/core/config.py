import os

# "demo-" project ids work offline with the Firebase emulators.
GCP_PROJECT = os.getenv("GCP_PROJECT", "demo-gosafe")
FIREBASE_STORAGE_BUCKET = os.getenv("FIREBASE_STORAGE_BUCKET", f"{GCP_PROJECT}.appspot.com")
ENABLE_DEV_ROUTES = os.getenv("ENABLE_DEV_ROUTES") == "true"
CHECKIN_TIMEOUT_SEC = float(os.getenv("CHECKIN_TIMEOUT_SEC", "90"))
EMULATOR = bool(os.getenv("FIRESTORE_EMULATOR_HOST"))
# Sahabat-AI behind any OpenAI-compatible endpoint (vLLM, Ollama, hosted). Empty: rule-based reviews.
LLM_BASE_URL = os.getenv("LLM_BASE_URL", "")
LLM_API_KEY = os.getenv("LLM_API_KEY", "")
LLM_MODEL = os.getenv("LLM_MODEL", "GoToCompany/gemma2-9b-cpt-sahabatai-v1-instruct")
# Fallback when Sahabat-AI isn't set up or fails: Gemini through its OpenAI-compatible endpoint.
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_MODEL = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
# Decision emails to the rider and driver (any SMTP server with STARTTLS). Empty SMTP_HOST: logged, not sent.
SMTP_HOST = os.getenv("SMTP_HOST", "")
SMTP_PORT = int(os.getenv("SMTP_PORT", "587"))
SMTP_USER = os.getenv("SMTP_USER", "")
SMTP_PASSWORD = os.getenv("SMTP_PASSWORD", "")
EMAIL_FROM = os.getenv("EMAIL_FROM", "GoSafe <no-reply@gosafe.test>")
GEMINI_BASE_URL = os.getenv("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta/openai")
# Cloudflare R2 for ride audio. When R2_BUCKET is set it replaces Firebase Storage and the Storage emulator.
R2_ACCOUNT_ID = os.getenv("R2_ACCOUNT_ID", "")
R2_ACCESS_KEY_ID = os.getenv("R2_ACCESS_KEY_ID", "")
R2_SECRET_ACCESS_KEY = os.getenv("R2_SECRET_ACCESS_KEY", "")
R2_BUCKET = os.getenv("R2_BUCKET", "")
