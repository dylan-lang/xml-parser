module: simple-xml
author: Hannes Mehnert <hannes@mehnert.org>
copyright: See LICENSE in this distribution for details.

/*
BUGS:
* with-xml doesn't preserve alphabetic case of attribute names (and probably
  element names), due to use of ?:name in the macro.  It should probably use
  ?:expression instead, and one would have to use strings for element and
  attribute names.  More verbose, but more accurate and also allows easily
  generating elements and attributes whose names aren't known at compile time.
  From #dylan: "<housel> SGML was normally configured to be case-insensitive,
  so HTML 4 doesn't care about the case, but it does matter for XML in general
  and XHTML in particular"
  Also: "<|Agent> Plus, XML names can contain periods and colons in namespaces."
*with-xml:collect only works for elements, not for lists of elements
*passing around lists and elements is not the way to do it performant...
*comment elements are missing
*the following doesn't work (reference to undefined binding "collect" (but
 collect is defined unhygienic in with-xml macro, do-clause, any ideas?
 bug in functional-developer?)
 define macro add-form-helper
   { add-form-helper(?type:name) end }
     => { define method add-form (type == ?#"type")
            with-xml()
              form (action => "/edit", \method => "post")
              {
                div (class => "edit")
                {
                  do(for (slot in ?type.slot-descriptors)
                       let name = slot.slot-getter.debug-name;
                       collect(with-xml()
                                 text(name)
                               end);
                       collect(with-xml()
                                 input(type => "text",
                                       name => name)
                               end);
                       collect(with-xml() br end);
                     end;
                  input(type => "submit",
                        name => "add-button",
                        value => "Add")
                }
              }
            end;
          end; }
 end;


USAGE
=====

with-xml()
  html {
    head {
      title("foo")
    },
    body {
      div(id => "foobar",
          class => "narf") {
        a("here", href => "http://www.foo.com"),
        a(href => "http://www.ccc.de/"),
        text("foobar"),
        ul {
          li("foo"),
          br,
          li("bar"),
          br
        }
      }
    }
  }
end;

generates:

<html>
  <head>
    <title>foo</title>
  </head>
  <body>
    <div id="foobar" class="narf">
      <a href="http://www.foo.com">here</a>
      <a href="http://www.ccc.de/"/>
      foobar
      <ul>
        <li>foo</li>
        <br/>
        <li>bar</li>
        <br/>
      </ul>
    </div>
  </body>
</html>
*/

define macro with-xml-builder
  { with-xml-builder ()
      ?body:*
    end }
   => { begin
          let doc = make(<document>,
                         children: list(with-xml() ?body end));
          transform(doc, make(<add-parents>));
          doc;
        end; }
end macro with-xml-builder;

define macro with-xml
  { with-xml () ?element end }
   => { begin
          ?element[0]
        end; }

  element:
   { ?:name } => { list(make(<element>, name: ?"name")) }
   { text ( ?value:expression ) } => { list(make(<char-string>,
                                                 text: ?value)) }
   { !attribute(?attribute) }
    => { list(?attribute) }
   { do(?:body) }
    => { begin
           let res = make(<stretchy-vector>);
           local method ?=collect(element)
                   res := add!(res, element)
                 end;
           let body-res = ?body;
           if (res.size > 0)
             res;
           elseif (body-res)
             if (instance?(body-res, <sequence>))
               body-res;
             else
               list(body-res);
             end;
           else
             make(<list>)
           end;
         end }
   { ?:name { ?element-list } }
    => { list(make(<element>,
                   children: concatenate(?element-list),
                   name: ?"name")) }
   { ?:name ( ?attribute-list ) { ?element-list } }
    => { list(make(<element>,
                   children: concatenate(?element-list),
                   name: ?"name",
                   attributes: vector(?attribute-list))) }
   { ?:name ( ?value:expression ) }
    => { list(make(<element>,
                   children: list(make(<char-string>,
                                       text: ?value)),
                   name: ?"name")) }
   { ?:name ( ?value:expression, ?attribute-list ) }
    => { list(make(<element>,
                   children: list(make(<char-string>,
                                        text: ?value)),
                   name: ?"name",
                   attributes: vector(?attribute-list))) }
   { ?:name ( ?attribute-list ) }
    => { list(make(<element>,
                   name: ?"name",
                   attributes: vector(?attribute-list))) }
   //{ comment ( ?value:expression ) } =>  { make-comment(?value) }

  element-list:
   { } => { }
   { ?element, ... } => { ?element, ... }

  attribute-list:
   { } => { }
   { ?attribute, ... } => { ?attribute, ... }

  attribute:
   { ?key:name => ?value:expression }
    => { make(<attribute>,
              name: ?"key",
              value: ?value) }
   { ?ns:name :: ?key:name => ?value:expression }
    => { make(<attribute>,
              name: concatenate(?"ns" ## ":", ?"key"),
              value: ?value) }
end macro with-xml;

define method add-attribute (element :: <element>, attribute :: <attribute>)
 => (res :: <element>)
  // prevent equal attribute names
  let existing-attribute = find-key(element.attributes, method (a :: <attribute>)
                                                          a.name = attribute.name
                                                        end);
  if (existing-attribute)
    aref(element.attributes, existing-attribute) := attribute;
  else
    element.attributes := add(element.attributes, attribute);
  end if;
  element;
end method add-attribute;

define method remove-attribute (element :: <element>, attribute)
  element.attributes := remove(element.attributes, attribute,
                          test: method (a :: <attribute>, b)
                            a.name = as(<symbol>, b);
                          end);
end method remove-attribute;

define method attribute (element :: <element>, attribute-name)
   => (res :: false-or(<attribute>));
  let pos = find-key(element.attributes, method (a)
                                          a.name = as(<symbol>, attribute-name);
                                        end);
  if (pos)
    aref(element.attributes, pos);
  else
    #f;
  end if;
end method attribute;


define open generic elements (element :: <element>, name :: <object>) => (res :: <sequence>);

// How about calling this find-children ?
define method elements (element :: <element>, element-name)
 => (res :: <sequence>);
  choose(method (a)
            a.name = as(<symbol>, element-name)
          end, element.node-children);
end method elements;


define open generic add-element (element :: <element>, node :: <xml>);

define method add-element (element :: <element>, node :: <xml>)
 => (res :: <element>);
  element.node-children := add(element.node-children, node);
  if (object-class(node) = <element>)
    node.element-parent := element;
  end if;
  element;
end method add-element;

define method remove-element (element :: <element>, node-name, #key count: element-count)
 => (res :: <element>);
  element.node-children := remove(element.node-children, node-name, count: element-count,
                          test: method (a :: <element>, b)
                                  a.name = as(<symbol>, b);
                                end);
  element;
end  method remove-element;

define open generic import-element (element :: <element>, node :: <element>);

define method import-element (element :: <element>, node :: <element>)
  for (child in node.node-children)
    add-element(element, child);
  end for;
  for (attribute in node.attributes)
    add-attribute(element, attribute);
  end for;
end method import-element;

define generic prefix (object :: <object>) => (res :: <string>);

define method prefix (element :: <element>)
 => (res :: <string>);
  prefix(element.name);
end method prefix;

define method prefix (name :: type-union(<string>, <symbol>))
  => (res :: <string>);
  split(as(<string>, name), ':')[0];
end method prefix;

define method prefix-setter (prefix :: <string>, element :: <element>)
  if (~member?(':', as(<string>, element.name)))
    element.name := as(<symbol>, concatenate(prefix, ":", as(<string>, element.name)));
  end if;
  element;
end method prefix-setter;


define generic real-name (object :: <object>) => (res :: <string>);

define method real-name (element :: <element>)
 => (res :: <string>);
  real-name(element.name);
end method real-name;

define method real-name (name :: type-union(<string>, <symbol>))
 => (res :: <string>);
  split(as(<string>, name), ':')[1];
end method real-name;

define method namespace (element :: <element>)
 => (xmlns :: false-or(<string>));
  let xmlns = attribute(element, "xmlns");
  xmlns & xmlns.attribute-value;
end method namespace;

define method add-namespace (element :: <element>, ns :: <string>)
  => (res :: <element>);
  add-attribute(element, make(<attribute>, name: "xmlns", value: ns));
  element;
end method add-namespace;

define method remove-namespace (element :: <element>)
 => (res :: <element>);
  remove-attribute(element, "xmlns");
  element;
end method remove-namespace;

define method replace-element-text (element :: <element>, node :: <string>, text :: <string>)
  let replace-element = #f;
  let replace-elements = elements(element, node);
  if (empty?(replace-elements))
    replace-element := make(<element>, name: node);
    add-element(element, replace-element);
  else
    replace-element := first(replace-elements);
  end if;
  replace-element.text := text;
end method replace-element-text;

define method start-tag (element :: <element>)
 => (tag :: <string>);
  let stream = make(<string-stream>, direction: #"output");
  let state = make(<printing>, stream: stream);
  print-opening(element, stream);
  print-attributes(element.attributes, state);
  print-closing(element, stream);
  stream-contents(stream);
end method start-tag;

define function parents (element :: <element>) => (element-parents :: <sequence>);
  let element :: false-or(<element>) = element;
  let parents = #();
  while (element)
    element := instance?(element.element-parent, <element>) & element.element-parent;
    element & (parents := add!(parents, element));
  end while;
  parents;
end function parents;
