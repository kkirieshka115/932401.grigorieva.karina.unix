#!/bin/sh

if [ "$#" -ne 1 ]; then
    echo "Ошибка: необходимо указать ровно один исходный файл" >&2
    echo "Использование: $0 <исходный_файл>" >&2
    exit 1
fi

SOURCE=$1

if [ ! -f "$SOURCE" ] || [ ! -r "$SOURCE" ]; then
    echo "Ошибка: файл '$SOURCE' не найден или недоступен для чтения" >&2
    exit 2
fi

OUTPUT=$(sed -n -e 's|^[[:space:]]*//[[:space:]]*Output:[[:space:]]*||p' -e 's|^[[:space:]]*%[[:space:]]*Output:[[:space:]]*||p' "$SOURCE" | head -n 1 | tr -d '\r')

if [ -z "$OUTPUT" ]; then
    echo "Ошибка: не найден комментарий 'Output: <имя_выходного_файла>'" >&2
    exit 3
fi

case "$OUTPUT" in
    */*|.|..)
        echo "Ошибка: после 'Output:' должно быть указано только имя файла без пути" >&2
        exit 4
        ;;
esac

WORK_DIR=

cleanup() {
    rc=$?
    trap - EXIT HUP INT QUIT PIPE TERM
    if [ -n "$WORK_DIR" ] && [ -d "$WORK_DIR" ]; then
        rm -rf -- "$WORK_DIR"
    fi
    exit "$rc"
}

trap cleanup EXIT HUP INT QUIT PIPE TERM

WORK_DIR=$(mktemp -d) || {
    echo "Ошибка: не удалось создать временный каталог" >&2
    exit 5
}

SOURCE_DIR=$(cd "$(dirname "$SOURCE")" && pwd) || {
    echo "Ошибка: не удалось определить каталог исходного файла" >&2
    exit 6
}
SOURCE_NAME=$(basename "$SOURCE")

if ! cp "$SOURCE" "$WORK_DIR/$SOURCE_NAME"; then
    echo "Ошибка: не удалось скопировать исходный файл во временный каталог" >&2
    exit 7
fi

cd "$WORK_DIR" || {
    echo "Ошибка: не удалось перейти во временный каталог" >&2
    exit 8
}

case "$SOURCE_NAME" in
    *.c)
        echo "Сборка программы на C..."
        cc -Wall -Wextra -pedantic -O2 -o "$OUTPUT" "$SOURCE_NAME" >build.log 2>&1
        BUILD_RESULT=$?
        ;;
    *.cpp|*.cxx|*.cc)
        echo "Сборка программы на C++..."
        c++ -Wall -Wextra -pedantic -O2 -o "$OUTPUT" "$SOURCE_NAME" >build.log 2>&1
        BUILD_RESULT=$?
        ;;
    *.tex)
        echo "Сборка документа TeX..."
        pdflatex -interaction=nonstopmode -halt-on-error "$SOURCE_NAME" >build.log 2>&1
        BUILD_RESULT=$?
        if [ "$BUILD_RESULT" -eq 0 ]; then
            GENERATED_PDF="${SOURCE_NAME%.tex}.pdf"
            if [ -f "$GENERATED_PDF" ] && [ "$GENERATED_PDF" != "$OUTPUT" ]; then
                mv -- "$GENERATED_PDF" "$OUTPUT"
            fi
        fi
        ;;
    *)
        echo "Ошибка: неподдерживаемый тип файла '$SOURCE_NAME' (ожидаются .c, .cpp, .tex)" >&2
        exit 9
        ;;
esac

if [ "$BUILD_RESULT" -ne 0 ]; then
    echo "Ошибка: сборка завершилась с кодом $BUILD_RESULT" >&2
    cat build.log >&2
    exit 10
fi

if [ ! -f "$OUTPUT" ]; then
    echo "Ошибка: выходной файл '$OUTPUT' не был создан" >&2
    exit 11
fi

if ! cp -- "$OUTPUT" "$SOURCE_DIR/$OUTPUT"; then
    echo "Ошибка: не удалось скопировать '$OUTPUT' в '$SOURCE_DIR'" >&2
    exit 12
fi

echo "Успешно: создан файл '$SOURCE_DIR/$OUTPUT'"
