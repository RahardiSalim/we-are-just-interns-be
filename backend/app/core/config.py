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
GEMINI_BASE_URL = os.getenv("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta/openai")
