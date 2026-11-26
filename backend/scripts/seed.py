"""Create the 6 demo accounts with role claims, then load demo data.

Run from backend/:  SEED_PASSWORD=... uv run python -m scripts.seed
Uses local ADC, or the emulators when FIREBASE_AUTH_EMULATOR_HOST / FIRESTORE_EMULATOR_HOST are set.
Accounts: <uid>@gosafe.test for each uid in app/services/seed.py USERS.
"""

import os

from firebase_admin import auth

from app.core.firebase import init
from app.services.seed import USERS, email, seed_data


def main() -> None:
    password = os.environ["SEED_PASSWORD"]  # demo-only; set it in your shell, never commit it
    app = init()
    for u in USERS:
        fields = {"email": email(u["uid"]), "password": password, "display_name": u["displayName"]}
        try:
            auth.update_user(u["uid"], app=app, **fields)
        except auth.UserNotFoundError:
            auth.create_user(uid=u["uid"], app=app, **fields)
        auth.set_custom_user_claims(u["uid"], {"role": u["role"]}, app=app)
        print(f"{u['role']:6} {email(u['uid'])}")
    print(seed_data())


if __name__ == "__main__":
    main()
