import zh_hans from "./i18n/zh_hans.json" with { type: "json" };
import zh_hant from "./i18n/zh_hant.json" with { type: "json" };
import es from "./i18n/es.json" with { type: "json" };
import ar from "./i18n/ar.json" with { type: "json" };
import fr from "./i18n/fr.json" with { type: "json" };
import ru from "./i18n/ru.json" with { type: "json" };
import de from "./i18n/de.json" with { type: "json" };
import ja from "./i18n/ja.json" with { type: "json" };
import mr from "./i18n/mr.json" with { type: "json" };
import pes from "./i18n/pes.json" with { type: "json" };
import it from "./i18n/it.json" with { type: "json" };
import ro from "./i18n/ro.json" with { type: "json" };
import hr from "./i18n/hr.json" with { type: "json" };
import nl from "./i18n/nl.json" with { type: "json" };
import hu from "./i18n/hu.json" with { type: "json" };
import sv from "./i18n/sv.json" with { type: "json" };
import ca from "./i18n/ca.json" with { type: "json" };
import br from "./i18n/br.json" with { type: "json" };
import cs from "./i18n/cs.json" with { type: "json" };
import fa from "./i18n/fa.json" with { type: "json" };
import id from "./i18n/id.json" with { type: "json" };
import ko from "./i18n/ko.json" with { type: "json" };
import pl from "./i18n/pl.json" with { type: "json" };
import uk from "./i18n/uk.json" with { type: "json" };
import nb from "./i18n/nb.json" with { type: "json" };
import config from "./config.js";

const prepTranslation = (langCode, langData) => {
  return langData.flatMap(t => {
    let target = t.reference.replace('Elm:', `%${langCode}:`) + "%";
    let replacement = t.definition;
    if (typeof target === "string" && target.startsWith(`%${langCode}`) && typeof replacement === "string" ) {
      // Regular replacement
      return [{ search: target
        , replace: replacement.replace('\n', '\\n').replace(/'/g,"\\'")
        , flags : 'g'
      }];
    } else if (replacement === null) {
      return [{ search: target
        , replace: t.term.replace(/'/g, "\\'")
        , flags : 'g'
      }];
    } else if (t.hasOwnProperty("term_plural") && typeof replacement == "object" && replacement.hasOwnProperty("one")) {
      // Plural replacement
      let singReplace = replacement.one.replace(/'/g,"\\'");
      let plurReplace = replacement.other.replace(/'/g, "\\'");
      plurReplace = plurReplace == "" ? t.term_plural : plurReplace;
      return [
        { search: target+":0" , replace: singReplace, flags : 'g' },
        { search: target+":1" , replace: plurReplace, flags:  'g' }];
    } else {
      return [];
    }
  });
}

const zhHansT = prepTranslation("zh_hans", zh_hans);
const zhHantT = prepTranslation("zh_hant", zh_hant);
const esT = prepTranslation("es", es);
const arT = prepTranslation("ar", ar);
const frT = prepTranslation("fr", fr);
const ruT = prepTranslation("ru", ru);
const deT = prepTranslation("de", de);
const jaT = prepTranslation("ja", ja);
const mrT = prepTranslation("mr", mr);
const pesT = prepTranslation("pes", pes);
const itT = prepTranslation("it", it);
const roT = prepTranslation("ro", ro);
const hrT = prepTranslation("hr", hr);
const nlT = prepTranslation("nl", nl);
const huT = prepTranslation("hu", hu);
const svT = prepTranslation("sv", sv);
const caT = prepTranslation("ca", ca);
const brT = prepTranslation("br", br);
const csT = prepTranslation("cs", cs);
const faT = prepTranslation("fa", fa);
const idT = prepTranslation("id", id);
const koT = prepTranslation("ko", ko);
const plT = prepTranslation("pl", pl);
const ukT = prepTranslation("uk", uk);
const nbT = prepTranslation("nb", nb);

const allLanguageStrings = [].concat(zhHansT, zhHantT, esT, arT, frT, ruT, deT, jaT,mrT, pesT, itT, roT, hrT, nlT, huT, svT, caT, brT, csT, faT, idT, koT, plT, ukT, nbT)
const otherReplacements = [
  { search: '{%SUPPORT_EMAIL%}', replace: config.SUPPORT_EMAIL, flags: 'g' },
  { search: '{%SUPPORT_URGENT_EMAIL%}', replace: config.SUPPORT_URGENT_EMAIL, flags: 'g' },
  { search: '{%HOMEPAGE_URL%}', replace: config.HOMEPAGE_URL, flags: 'g' },
  { search: '{%TESTIMONIAL_URL%}', replace: config.TESTIMONIAL_URL, flags: 'g' },
  { search: '{%VOX_EMPORIUM_SALT%}', replace: config.VOX_EMPORIUM_SALT, flags: 'g' },
]

const allReplacements = allLanguageStrings.concat(otherReplacements);

/**
 * @type {import("elm-watch/elm-watch-node").Postprocess}
 */
export default function postprocess({ code, compilationMode }) {
  if (compilationMode === 'optimize') {
    allReplacements.forEach(replacement => {
      code = code.replaceAll(replacement.search, replacement.replace);
    });
  }

  return code;
}