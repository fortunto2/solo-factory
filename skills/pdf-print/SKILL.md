---
name: solo-pdf-print
description: Use when "сделай пдф", "make a PDF", "на печать", "распечатать", "prepare for A4", "печатные карточки", "PDF из markdown", or a PDF renders but the page layout has to be checked before handing it over. Covers WeasyPrint on macOS, why headless Chrome hangs, page breaks, page numbers and Cyrillic.
license: MIT
metadata:
  author: fortunto2
  version: "1.0.0"
  openclaw:
    emoji: "🖨️"
allowed-tools: Bash, Read, Write, Edit
argument-hint: "[что печатаем, напр. «отчёт из markdown» или «карточки A4»]"
---

# HTML → печатный PDF

Инструмент — **WeasyPrint**. Он один из трёх кандидатов умеет то, ради чего печать
вообще затевается: колонтитулы с номерами страниц, предсказуемые разрывы и
управление через `@page`.

## 0. Сначала то, на чём теряют час

**На macOS WeasyPrint падает на импорте**, хотя установлен:

```
OSError: cannot load library 'libgobject-2.0-0'
```

Библиотеки стоят в homebrew, но не в пути загрузчика. Лечится одной переменной:

```bash
export DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib
uv run --with weasyprint python build.py
```

⚠️ Переменная нужна **и в скрипте, и в CI, и в хуке** — окружение хука отличается
от окружения оболочки. Если её негде поставить, в начале скрипта:

```python
import os; os.environ.setdefault("DYLD_FALLBACK_LIBRARY_PATH", "/opt/homebrew/lib")
```

## 1. Чем НЕ печатать

| Инструмент | Что не так |
|---|---|
| **headless Chrome** `--print-to-pdf` | Печатает, но **не завершается**: процесс висит до таймаута. Проверено 13.09.2026 — PDF записался, а `subprocess` упал по `TimeoutExpired` через 180 с. И он **не умеет `@page` margin-boxes**, то есть номеров страниц не будет вовсе |
| **wkhtmltopdf** | Движок Qt WebKit: ни flexbox, ни `columns`, ни современных `break-*` |
| **pandoc → LaTeX** | Хорош для книги, избыточен для одностраничника; кириллица требует настройки шрифтов |

Chrome остаётся уместен ровно в одном случае: когда страницу **рисует JavaScript**.
WeasyPrint скрипты не выполняет — данные надо отдать уже в HTML.

## 2. Скелет, который работает

```python
# /// script
# dependencies = ["weasyprint"]
# ///
from weasyprint import HTML
HTML(filename="out.html").write_pdf("out.pdf")
```

```css
@page {
  size: A4 portrait;               /* landscape — для лент и таблиц */
  margin: 15mm 14mm 16mm 14mm;
  @bottom-right { content: counter(page) " / " counter(pages);
                  font: 8pt Georgia, serif; color: #888; }
}
@page :first { @bottom-right { content: ""; } }   /* на титуле номер не нужен */

section { break-before: page; }     /* не page-break-before: он устарел */
.card    { break-inside: avoid; }   /* карточку не рвать между страницами */
h3       { break-after: avoid; }    /* заголовок не бросать внизу листа */
```

Единицы — **мм и pt**, не px: на бумаге пиксель ничего не значит. Ширину карточек
задавать в мм, чтобы после разрезания они были предсказуемого размера.

## 3. Кириллица и башкирские буквы

Системные Georgia / Times New Roman покрывают кириллицу целиком, **включая
ә ҙ ҡ ң ө ҫ ү һ**. Веб-шрифты для печати не нужны и только тормозят сборку.
Если шрифт всё же подключается — проверить именно эти буквы: подстановка
глифа из другого шрифта видна как скачок начертания в середине слова.

## 4. Проверять глазами, а не `pdftotext`

`pdftotext` вытаскивает текст в порядке потока и **не покажет ни наложений, ни
обрезанных блоков, ни пустых страниц**. Смотреть надо картинку:

```bash
pdftoppm -f 1 -l 2 -r 76 -png out.pdf /tmp/page   # первые две страницы в PNG
```

и открыть PNG. Что ловится только так:
- текст, вылезший за рамку карточки фиксированной высоты;
- полстраницы пустоты из-за `break-before` на пустой секции;
- **дублирование**: краткая выжимка и полный текст, где выжимка — цитата из него;
- эмодзи, которые на экране маркеры, а на бумаге — пёстрые картинки. В печать
  их обычно вырезают, структуру несут рамки и подписи.

## 5. Markdown → PDF

Готовый пример с русской типографикой — `6-crm/bin/md_to_pdf.py`: markdown +
weasyprint, таблицы, `@bottom-right`, жёсткий разрыв между файлами.

```bash
DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib \
  uv run python bin/md_to_pdf.py --out OUT.pdf FILE1.md FILE2.md
```

## 6. Когда печатают для людей, а не для архива

- **Размер шрифта — от 10pt.** 8pt читается на экране и не читается на бумаге.
- **Одна мысль — один блок.** Врезка с вопросом заметнее абзаца с вопросом.
- **Номер страницы обязателен**, если листов больше трёх: иначе рассыпавшуюся
  стопку не собрать.
- **Карточки на разрез** — рамка `.8pt` сплошная, поля внутри не меньше 4pt,
  и запас 2-3 мм на неточность резака.
- Печать бывает **чёрно-белой**: иерархия должна держаться на жирности и
  рамках, цвет — только подсказка.

## Связи

Стиль текста — `/solo:humanize`. Готовый генератор многостраничного документа
с деревом и карточками — `~/personal/family/bin/shezhere-print.py`.
