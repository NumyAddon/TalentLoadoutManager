local _, ns = ...;
if GetLocale() ~= "ruRU" then return; end

local L = ns.L;

L["Talent Loadout Manager"] = "Talent Loadout Manager";
L["Create"] = "Создать";
L["Import"] = "Импорт";
L["Save"] = "Сохранить";
L["Config"] = "Настройки";
L["Load"] = "Загрузить";
L["Load & Apply"] = "Загрузить и применить";
L["Export"] = "Экспорт";
L["Rename"] = "Переименовать";
L["Delete"] = "Удалить";
L["Locked"] = "Заблокирован";
L["Link to chat"] = "Ссылка в чат";

L["Create a new custom loadout"] = "Создать новый пользовательский набор";
L["Import a custom loadout from a string"] = "Импортировать набор из строки";
L["Save the current talents into the currently selected loadout"] = "Сохранить текущие таланты в выбранный набор";
L["Open the configuration UI"] = "Открыть настройки";

L["Toggle Sidebar"] = "Показать/скрыть боковую панель";
L["Shift + Click to move sidebar"] = "|cffeda55fShift + клик|r — переместить боковую панель на другую сторону.";
L["Right-Click to move sidebar inside"] = "|cffeda55fПКМ|r — переместить боковую панель внутрь интерфейса.";

L["Loadout name hint"] = "Всё до первого символа '||' не отображается. Так можно сортировать наборы с помощью префикса.";
L["Rename loadout (%s)"] = "Переименовать набор (%s)";
L["Create custom loadout"] = "Создать пользовательский набор";
L["Delete loadout (%s)?"] = "Удалить набор (%s)?";
L["Remove loadout from list (%s)?"] = "Убрать набор из списка (%s)?";
L["Remove all loadouts from %s from the list?"] = "Убрать все наборы персонажа %s из списка?";
L["CTRL-C to copy"] = "CTRL-C чтобы скопировать";
L["CTRL-C to copy %s"] = "CTRL-C чтобы скопировать %s";

L["Import Custom Loadout"] = "Импорт пользовательского набора";
L["Import control label"] = "%s (также поддерживаются ссылки калькулятора Icy Veins)";
L["Automatically Apply the loadout on import"] = "Автоматически применять набор при импорте";
L["Auto apply on import tooltip"] = "Если включено, набор будет автоматически применён к персонажу при импорте.";
L["Import into currently selected custom loadout"] = "Импортировать в выбранный пользовательский набор";
L["Import into current loadout tooltip"] = "Если включено, билд будет импортирован в текущий выбранный набор.";
L["*importing into current loadout*"] = "*импорт в текущий набор*";

L["Left-Click to %s this loadout"] = "ЛКМ — %s этот набор";
L["Shift-Click to link to chat"] = "Shift + клик — ссылка в чат";
L["Right-Click for options"] = "ПКМ — меню действий";

L["Save current talents into loadout"] = "Сохранить текущие таланты в набор";
L["Lock loadout"] = "Заблокировать набор";
L["Lock loadout tooltip"] = "Блокировка не даёт сохранять изменения в набор.";
L["Set Blizzard base loadout"] = "Базовый набор Blizzard";
L["Open in TalentTreeViewer"] = "Открыть в TalentTreeViewer";
L["Remove from list"] = "Убрать из списка";
L["Remove all loadouts from this character from the list"] = "Убрать все наборы этого персонажа из списка";
L["Permanently hide all loadouts from this character"] = "Навсегда скрыть все наборы этого персонажа";
L["Loadouts from %s are now hidden. You can reset this in the config."] = "Наборы персонажа %s скрыты. Сброс доступен в настройках.";

L["Custom Loadout %s"] = "Пользовательский набор %s";
L["BlizzMove incompatible"] = "%s несовместим с текущей версией BlizzMove, обновите аддон.";

L["Version: %s"] = "Версия: %s";
L["Leveling build description"] = [[TalentLoadoutManager поддерживает импорт билдов для прокачки через любую строку импорта или внутриигровую ссылку с данными прокачки, а также через ссылки калькулятора Icy Veins.
Вы можете создать билд для прокачки сами — в калькуляторе Icy Veins или в игре с помощью аддона Talent Tree Viewer
]];
L["Auto Re-Apply Loadout on Level Up"] = "Автоповтор набора при повышении уровня";
L["Auto Re-Apply Loadout on Level Up desc"] = "Автоматически заново применять текущий набор талантов при повышении уровня.";
L["Auto Scale"] = "Автомасштаб";
L["Auto Scale desc"] = "Автоматически масштабировать окно талантов под экран. (отключается при загруженных BlizzMove или TalentTreeTweaks)";
L["Auto Position"] = "Автопозиция";
L["Auto Position desc"] = "Автоматически перемещать окно талантов в центр экрана.";
L["Auto Apply"] = "Автоприменение";
L["Auto Apply desc"] = "Автоматически применять набор талантов при импорте или переключении.";
L["Add to SimC"] = "Добавлять в SimC";
L["Add to SimC desc"] = "Автоматически добавлять пользовательские наборы в SimulationCraft при использовании /simc.";
L["Reset Hidden Characters"] = "Сбросить скрытых персонажей";
L["Reset Hidden Characters desc"] = "Сбрасывает персонажей, чьи наборы были скрыты на боковой панели.";
L["Sidebar Colors"] = "Цвета боковой панели";
L["Selected Loadout Text"] = "Текст выбранного набора";
L["Selected Loadout Text desc"] = "Цвет текста выбранного набора на боковой панели.";
L["Selected Loadout Background"] = "Фон выбранного набора";
L["Selected Loadout Background desc"] = "Цвет фона выбранного набора на боковой панели.";
L["Selected Loadout Highlight"] = "Подсветка выбранного набора";
L["Selected Loadout Highlight desc"] = "Цвет фона выбранного набора при наведении.";
L["Loadout Text"] = "Текст набора";
L["Loadout Text desc"] = "Цвет текста наборов на боковой панели.";
L["Loadout Background"] = "Фон набора";
L["Loadout Background desc"] = "Цвет фона наборов на боковой панели.";
L["Loadout Highlight"] = "Подсветка набора";
L["Loadout Highlight desc"] = "Цвет фона набора при наведении.";
L["Sidebar Background"] = "Фон боковой панели";
L["Sidebar Background desc"] = "Цвет фона боковой панели.";
L["Reset All Colors"] = "Сбросить все цвета";
L["Reset All Colors desc"] = "Сбросить все цвета боковой панели к значениям по умолчанию.";

L["Failed to serialize loadout %s"] = "Не удалось сериализовать набор %s";
L["You have not unlocked talents yet."] = "Таланты ещё не разблокированы.";
L["Too many blizzard loadouts"] = "Слишком много наборов Blizzard. Удалите один, чтобы переключиться на пользовательский набор.";
L["Failed to create new loadout."] = "Не удалось создать новый набор.";
L["Failed to fully apply loadout. %s entries could not be purchased."] = "Не удалось полностью применить набор. Не удалось взять %s записей.";
L["Failed to commit loadout."] = "Не удалось сохранить набор.";
L["Zygor warning"] = "Включён советник талантов Zygor Guides. Это может вызывать подвисания при смене наборов. Отключите эту функцию и сообщите автору Zygor Guides.";

L["Automatically re-applying loadout"] = "Автоматически повторно применяется набор %s. Отключить: /TLM.";
L["New Talent Learned:"] = "Изучен новый талант:";
L["Talent Upgraded:"] = "Талант улучшен:";
L["to rank"] = "до ранга";

L["Import string is corrupt"] = "Строка импорта повреждена, несовпадение типа узла nodeID %d. Будет выбран первый вариант.";
L["IcyVeins import error"] = "Ошибка импорта URL Icy Veins: не найден узел для индекса %s - %s";
L["Invalid URL"] = "Неверный URL";
L["Wrong class"] = "Неверный класс";
L["Loadout not found"] = "Набор не найден";
L["Could not find newly imported loadout"] = "Не удалось найти только что импортированный набор";
