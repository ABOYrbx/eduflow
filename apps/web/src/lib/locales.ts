import { registerCatalogs } from "./i18n";
import af from "../../messages/af.json";
import ar from "../../messages/ar.json";
import ca from "../../messages/ca.json";
import cs from "../../messages/cs.json";
import da from "../../messages/da.json";
import de from "../../messages/de.json";
import el from "../../messages/el.json";
import es from "../../messages/es.json";
import fi from "../../messages/fi.json";
import fr from "../../messages/fr.json";
import he from "../../messages/he.json";
import hu from "../../messages/hu.json";
import it from "../../messages/it.json";
import ja from "../../messages/ja.json";
import ko from "../../messages/ko.json";
import nl from "../../messages/nl.json";
import no from "../../messages/no.json";
import pl from "../../messages/pl.json";
import pt from "../../messages/pt.json";
import ro from "../../messages/ro.json";
import ru from "../../messages/ru.json";
import sr from "../../messages/sr.json";
import sv from "../../messages/sv.json";
import tr from "../../messages/tr.json";
import uk from "../../messages/uk.json";
import vi from "../../messages/vi.json";
import zh from "../../messages/zh.json";

// Nur für Server-Code (Layout, Routen): registriert alle Kataloge einmalig.
// WICHTIG: Neue Crowdin-Sprache = hier Import + Eintrag ergänzen, sonst
// bleibt sie ungenutzt (t() fällt dann auf Englisch zurück).
registerCatalogs({
  af, ar, ca, cs, da, de, el, es, fi, fr, he, hu, it, ja, ko, nl, no,
  pl, pt, ro, ru, sr, sv, tr, uk, vi, zh,
});
