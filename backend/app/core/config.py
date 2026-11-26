import os

# "demo-" project ids work offline with the Firebase emulators.
GCP_PROJECT = os.getenv("GCP_PROJECT", "demo-gosafe")
FIREBASE_STORAGE_BUCKET = os.getenv("FIREBASE_STORAGE_BUCKET", f"{GCP_PROJECT}.appspot.com")
ENABLE_DEV_ROUTES = os.getenv("ENABLE_DEV_ROUTES") == "true"
