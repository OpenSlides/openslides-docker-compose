import os
import sys
from importlib.util import spec_from_loader, module_from_spec
from importlib.machinery import SourceFileLoader

# List of all interesting variables
variables = (
    "SECRET_KEY",
    "ENABLE_SAML",
    "ENABLE_ELECTRONIC_VOTING",
    "JITSI_DOMAIN",
    "JITSI_ROOM_NAME",
    "JITSI_ROOM_PASSWORD")

# prepare temp file
with open("settings.py", "r") as f:
    with open("settings_tmp.py", "w") as out:
        for line in f:
            if "openslides.global_settings" in line:
                out.write("INSTALLED_APPS = []\n")
                out.write("INSTALLED_PLUGINS = []\n")
                out.write("STATICFILES_DIRS = []\n")
            else:
                out.write(line)

# load the settings_tmp.py
spec = spec_from_loader("settings_tmp", SourceFileLoader("settings_tmp", "settings_tmp.py"))
settings = module_from_spec(spec)
spec.loader.exec_module(settings)

# Extract all interesting variables.
values = {}
for variable in variables:
    if hasattr(settings, variable):
        values[variable] = getattr(settings, variable)

try:
    os.mkdir("secrets")
except FileExistsError:
    pass

with open("secrets/django.env", "w") as django:
    django.write(f"DJANGO_SECRET_KEY='{values.pop('SECRET_KEY')}'\n")

with open(".env", "a") as env:
    keys = sorted(values.keys())
    for k in keys:
        env.write(f"{k}={values[k]}\n")

os.remove("settings_tmp.py")

