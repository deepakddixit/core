<?php
print_unescaped($l->t("Hey there,\n\njust letting you know that %s shared %s with you.\nView it: %s\n\n", [$_['user_displayname'], $_['filename'], $_['link']]));
if (isset($_['expiration'])) {
	print_unescaped($l->t("The share will expire on %s.", [$_['expiration']]));
	print_unescaped("\n\n");
}
if (isset($_['personal_note'])) {
	// TRANSLATORS personal note in share notification email
	print_unescaped($l->t("Personal note from the sender: %s.", [$_['personal_note']]));
	print_unescaped("\n\n");
}
// TRANSLATORS term at the end of a mail
p($l->t("Cheers!"));
?>

--
<?php p($theme->getName() . ' - ' . $theme->getSlogan()); ?>
<?php print_unescaped("\n".$theme->getBaseUrl());
