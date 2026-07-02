# Одноразовые скрипты

## convert_pdf.py

Разовая конвертация `1500_english_words_US_RU.pdf` → `data/core-1500.json` (канонический формат пачки, см. README в корне). Скрипт больше не поддерживается: будущие пачки поставляются сразу в JSON.

```sh
python3 -m venv .venv
.venv/bin/pip install pdfplumber
.venv/bin/python scripts/convert_pdf.py
```
