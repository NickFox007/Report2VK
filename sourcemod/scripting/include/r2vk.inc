#if defined _r2vk_included    // Если директива  _base_stats_included объявлена
    #endinput // Прекращаем чтение файла (Если компилятор встречает #endinput в файле, то он игнорирует весь ниженаписанный код)
#endif // Окончание условия
#define _r2vk_included    // Объявляем директиву _base_stats_included

native void R2VK_Send(const char[] text);
/**
 *	Отправляет сообщение через плагин R2VK
 *	-
 * @param text			Текст сообщения.
 *	-
 * @return					void
*/