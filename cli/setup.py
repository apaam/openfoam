from setuptools import setup

setup(
    data_files=[
        ("share/zsh/site-functions", ["phynexis_foam/_phynexis-foam"]),
        ("share/bash-completion/completions", ["completions/bash/phynexis-foam"]),
    ],
)
