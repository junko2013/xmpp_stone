import '../XmppAttribute.dart';
import '../XmppElement.dart';

class ReceiptSpamElement extends XmppElement {
  static String elementName = 'spam';
  ReceiptSpamElement() {
    name = elementName;
  }

  ReceiptSpamElement.build() {
    name = ReceiptSpamElement.elementName;
    addAttribute(XmppAttribute('xmlns', 'urn:xmpp:spam'));
  }

  static XmppElement? parse(parent) {
    return parent.children.firstWhere(
        (child) => (child.name == ReceiptSpamElement.elementName),
        orElse: () => null);
  }
}
